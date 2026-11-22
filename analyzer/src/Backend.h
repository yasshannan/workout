#pragma once

#include <QFileSystemWatcher>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include "Database.h"
#include "Importer.h"

// Backend : the one object the QML user interface talks to.
// main.cpp makes it available in QML under the name "backend".
//
// The division of work:
//   QML asks for data with   backend.rows("v_weekly")      -> rows of a view
//   QML changes a filter with backend.setFilter(...)        -> the views change
//   after every change "revision" goes up by one            -> the pages reload
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QString databasePath READ databasePath CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString importFolder READ importFolder NOTIFY importFolderChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    int revision() const { return m_revision; }
    QString databasePath() const { return m_db.filePath(); }
    QString lastError() const { return m_lastError; }
    QString importFolder() const { return m_importFolder; }

    // All rows of a view from sql/derived.sql, for example rows("v_weekly").
    Q_INVOKABLE QVariantList rows(const QString &view);
    // The first row of a view (an empty object if the view is empty).
    Q_INVOKABLE QVariantMap row(const QString &view);

    // Date range: "4w", "8w", "12w", "26w", "52w" or "all".
    Q_INVOKABLE void setRange(const QString &preset);
    // Date range typed by hand, as "YYYY-MM-DD". An empty text means "no limit".
    Q_INVOKABLE void setCustomRange(const QString &fromDay, const QString &toDay);
    // key is "exercise_id" or "muscle_id". An empty id clears the filter.
    Q_INVOKABLE void setFilter(const QString &key, const QString &id);
    Q_INVOKABLE void resetFilters();

    // What a page shows in detail: key is "sel_exercise" or "sel_muscle".
    // Does not raise "revision", the page reloads its own charts.
    Q_INVOKABLE void select(const QString &key, const QString &id);

    // Settings: key is "formula", "theme" or "animations".
    Q_INVOKABLE void setOption(const QString &key, const QVariant &value);

    // Import export files of the phone app. Returns one summary object per file.
    Q_INVOKABLE QVariantList importFiles(const QList<QUrl> &files);
    // Auto-import: the app watches this folder and imports every new .json
    // export file in it by itself (also right after the app starts).
    // Pass an empty url to switch it off.
    Q_INVOKABLE void setImportFolder(const QUrl &folder);
    // Look into the folder now. Returns one summary object per imported file.
    Q_INVOKABLE QVariantList scanImportFolder();

    // Write a full backup that the phone app can import. Returns true on success.
    Q_INVOKABLE bool exportBackup(const QUrl &file);

    // shares: secondary muscle id → how much one set counts for it (0.25, 0.5 or 0.75)
    Q_INVOKABLE bool setExerciseMuscles(const QString &exerciseId, const QStringList &primary, const QStringList &secondary,
                                        const QVariantMap &shares = QVariantMap());
    Q_INVOKABLE bool setMuscleTarget(const QString &muscleId, double targetMin, double targetMax);
    // Training level: 'beginner', 'intermediate' or 'advanced' sets all weekly targets at once.
    Q_INVOKABLE bool setLevel(const QString &level);

signals:
    void revisionChanged();
    void lastErrorChanged();
    void importFolderChanged();
    // Files were imported from the watched folder without a click.
    void autoImported(const QVariantList &summary);

private:
    bool setStateColumn(const QString &column, const QVariant &value);
    void applyPreset(const QString &preset);
    void changed();                       // raise "revision"
    void setError(const QString &text);
    QVariantList importPaths(const QStringList &paths);
    void watchFolder();

    Database m_db;
    Importer m_importer{m_db};
    int m_revision = 0;
    QString m_lastError;
    QString m_importFolder;
    QFileSystemWatcher m_watcher;
    QTimer m_scanTimer;                 // waits a moment, so a file is complete before it is read
};
