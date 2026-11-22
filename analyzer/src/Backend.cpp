#include "Backend.h"

#include <QDebug>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QStandardPaths>

#include <utility>

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    // The database lives in the user's AppData folder, for example
    // C:/Users/You/AppData/Roaming/WorkoutTracker/Workout Analyzer/workout.sqlite
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(folder);
    if (!m_db.open(folder + QStringLiteral("/workout.sqlite")))
        setError(QStringLiteral("Die Datenbank konnte nicht geöffnet werden: ") + m_db.lastError());

    // Auto-import. When something changes in the folder, wait 2 seconds (the
    // phone or OneDrive may still be writing the file), then look into it.
    m_scanTimer.setSingleShot(true);
    m_scanTimer.setInterval(2000);
    connect(&m_scanTimer, &QTimer::timeout, this, [this]() { scanImportFolder(); });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() { m_scanTimer.start(); });

    m_importFolder = m_db.value(QStringLiteral("SELECT value FROM meta WHERE key = 'import_folder'")).toString();
    watchFolder();
    // Look once shortly after start-up, for files that arrived while the app was closed.
    QTimer::singleShot(500, this, [this]() { scanImportFolder(); });
}

void Backend::watchFolder()
{
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    if (!m_importFolder.isEmpty() && QDir(m_importFolder).exists())
        m_watcher.addPath(m_importFolder);
}

void Backend::setImportFolder(const QUrl &folder)
{
    m_importFolder = folder.isEmpty() ? QString() : folder.toLocalFile();
    m_db.runBlock("save_meta", { {"key", QStringLiteral("import_folder")}, {"value", m_importFolder} });
    watchFolder();
    emit importFolderChanged();
    scanImportFolder();
}

QVariantList Backend::scanImportFolder()
{
    if (m_importFolder.isEmpty() || !QDir(m_importFolder).exists())
        return QVariantList();

    // Every .json file that is new, or that changed since it was imported.
    QStringList todo;
    const QFileInfoList files = QDir(m_importFolder).entryInfoList({ QStringLiteral("*.json") }, QDir::Files, QDir::Time | QDir::Reversed);
    for (const QFileInfo &file : files) {
        const QString modified = file.lastModified().toUTC().toString(Qt::ISODate);
        const QString known = m_db.value(QStringLiteral("SELECT modified FROM imported_files WHERE path = :path"),
                                         { {"path", file.absoluteFilePath()} }).toString();
        if (known != modified)
            todo.append(file.absoluteFilePath());
    }
    if (todo.isEmpty())
        return QVariantList();

    const QVariantList summary = importPaths(todo);
    // Remember the files, also the ones that failed: a broken file is not tried again
    // and again. If you fix or replace it, its time changes and it is tried once more.
    for (const QString &path : std::as_const(todo)) {
        m_db.runBlock("remember_file", {
            {"path", path},
            {"modified", QFileInfo(path).lastModified().toUTC().toString(Qt::ISODate)}
        });
    }
    emit autoImported(summary);
    return summary;
}

void Backend::changed()
{
    ++m_revision;
    emit revisionChanged();
}

void Backend::setError(const QString &text)
{
    m_lastError = text;
    qWarning().noquote() << text;
    emit lastErrorChanged();
}

QVariantList Backend::rows(const QString &view)
{
    // Only names like "v_weekly" are accepted, nothing else can be put into the SQL text.
    static const QRegularExpression validName(QStringLiteral("^v_[a-z0-9_]+$"));
    if (!validName.match(view).hasMatch()) {
        qWarning().noquote() << "Not a view name:" << view;
        return QVariantList();
    }
    return m_db.select(QStringLiteral("SELECT * FROM ") + view);
}

QVariantMap Backend::row(const QString &view)
{
    const QVariantList all = rows(view);
    return all.isEmpty() ? QVariantMap() : all.first().toMap();
}

// Write one column of the single row in the "state" table.
bool Backend::setStateColumn(const QString &column, const QVariant &value)
{
    static const QStringList columns = {
        "from_day", "to_day", "exercise_id", "muscle_id", "range_preset",
        "sel_exercise", "sel_muscle", "formula", "theme", "animations"
    };
    if (!columns.contains(column)) {
        qWarning().noquote() << "Unknown state column:" << column;
        return false;
    }
    return m_db.exec("UPDATE state SET " + column + " = :value", { {"value", value} });
}

// An empty text is stored as NULL, which the SQL reads as "no filter".
static QVariant textOrNull(const QString &text)
{
    return text.isEmpty() ? QVariant() : QVariant(text);
}

void Backend::applyPreset(const QString &preset)
{
    static const QHash<QString, int> weeks = { {"4w", 4}, {"8w", 8}, {"12w", 12}, {"26w", 26}, {"52w", 52} };
    if (weeks.contains(preset))
        m_db.runBlock("range_last_days", { {"days", weeks.value(preset) * 7 - 1} });
    else if (preset == QLatin1String("all"))
        m_db.runBlock("range_all");
    // any other value ("custom") keeps from_day and to_day as they are
    setStateColumn("range_preset", preset);
    m_db.runBlock("apply_filter");
}

void Backend::setRange(const QString &preset)
{
    m_db.begin();
    applyPreset(preset);
    m_db.commit();
    changed();
}

void Backend::setCustomRange(const QString &fromDay, const QString &toDay)
{
    m_db.begin();
    setStateColumn("from_day", textOrNull(fromDay));
    setStateColumn("to_day", textOrNull(toDay));
    applyPreset(QStringLiteral("custom"));
    m_db.commit();
    changed();
}

void Backend::setFilter(const QString &key, const QString &id)
{
    if (key != QLatin1String("exercise_id") && key != QLatin1String("muscle_id"))
        return;
    m_db.begin();
    setStateColumn(key, textOrNull(id));
    m_db.runBlock("apply_filter");
    m_db.commit();
    changed();
}

void Backend::resetFilters()
{
    m_db.begin();
    setStateColumn("exercise_id", QVariant());
    setStateColumn("muscle_id", QVariant());
    applyPreset(QStringLiteral("8w"));
    m_db.commit();
    changed();
}

void Backend::select(const QString &key, const QString &id)
{
    if (key == QLatin1String("sel_exercise") || key == QLatin1String("sel_muscle"))
        setStateColumn(key, textOrNull(id));
}

void Backend::setOption(const QString &key, const QVariant &value)
{
    if (key == QLatin1String("formula")) {
        m_db.begin();
        setStateColumn(key, value);
        m_db.runBlock("apply_filter");      // the estimated 1RM column depends on the formula
        m_db.commit();
        changed();
    } else if (key == QLatin1String("theme") || key == QLatin1String("animations")) {
        setStateColumn(key, value);
    }
}

QVariantList Backend::importFiles(const QList<QUrl> &files)
{
    QStringList paths;
    for (const QUrl &url : files)
        paths.append(url.toLocalFile());
    return importPaths(paths);
}

QVariantList Backend::importPaths(const QStringList &paths)
{
    QVariantList summary;
    for (const QString &path : paths) {
        const ImportResult result = m_importer.importFile(path);
        summary.append(QVariantMap{
            {"file", result.fileName},
            {"ok", result.ok},
            {"message", result.message},
            {"added", result.added},
            {"updated", result.updated},
            {"unchanged", result.unchanged}
        });
    }

    // Move the date range forward to the new data ("last 8 weeks" is counted
    // back from the newest export), then tell the pages to reload.
    m_db.begin();
    applyPreset(m_db.value("SELECT range_preset FROM state").toString());
    m_db.commit();
    changed();
    return summary;
}

bool Backend::exportBackup(const QUrl &file)
{
    const QString error = m_importer.writeBackup(file.toLocalFile());
    if (!error.isEmpty()) {
        setError(error);
        return false;
    }
    return true;
}

bool Backend::setExerciseMuscles(const QString &exerciseId, const QStringList &primary, const QStringList &secondary,
                                 const QVariantMap &shares)
{
    if (!m_importer.setExerciseMuscles(exerciseId, primary, secondary, shares))
        return false;
    m_db.runBlock("apply_filter");          // a muscle filter may now match different sets
    changed();
    return true;
}

bool Backend::setMuscleTarget(const QString &muscleId, double targetMin, double targetMax)
{
    if (targetMin < 0 || targetMax < targetMin)
        return false;
    const bool ok = m_db.runBlock("set_muscle_target", {
        {"id", muscleId},
        {"target_min", targetMin},
        {"target_max", targetMax}
    });
    if (ok)
        changed();
    return ok;
}

bool Backend::setLevel(const QString &level)
{
    static const QHash<QString, double> factors = {
        {QStringLiteral("beginner"), 0.7}, {QStringLiteral("intermediate"), 1.0}, {QStringLiteral("advanced"), 1.25}
    };
    if (!factors.contains(level))
        return false;
    const double factor = factors.value(level);
    const bool ok = m_db.runBlock("apply_level", { {"factor", factor}, {"factor_again", factor}, {"level", level} });
    if (ok)
        changed();
    return ok;
}
