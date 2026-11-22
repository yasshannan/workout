#include "Database.h"

#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QSqlError>
#include <QSqlRecord>

#include <utility>

// ┌──────────────────────────────────────────────────────────────────────────┐
// │  YOUR DATA SURVIVES EVERY UPDATE. Rules for every future change:          │
// │  - Tables only grow: add tables and columns (upgradeOldTables), never     │
// │    drop them or delete imported rows.                                     │
// │  - Raise kDataVersion whenever schema.sql, derived.sql or                 │
// │    upgradeOldTables() changes. A database file with a lower number is     │
// │    copied to "workout-vor-update.sqlite" (next to it) before it is        │
// │    opened and changed. Only the newest copy is kept.                      │
// └──────────────────────────────────────────────────────────────────────────┘
namespace {

constexpr int kDataVersion = 1;

// The number SQLite keeps as "PRAGMA user_version", read straight from the
// file without opening it: 4 bytes, big-endian, at byte 60 of the header.
// -1 if there is no file yet (first start) or it is no SQLite file.
int storedDataVersion(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return -1;
    const QByteArray head = file.read(100);
    if (head.size() < 100 || !head.startsWith("SQLite format 3"))
        return -1;
    const auto byteAt = [&head](int i) { return static_cast<quint32>(static_cast<uchar>(head.at(i))); };
    return static_cast<int>((byteAt(60) << 24) | (byteAt(61) << 16) | (byteAt(62) << 8) | byteAt(63));
}

// Before a new version of the app changes an existing database: keep a copy.
void copyBeforeUpgrade(const QString &filePath)
{
    const int stored = storedDataVersion(filePath);
    if (stored < 0 || stored >= kDataVersion)
        return;                                  // a new file, or already this version
    const QString copy = QFileInfo(filePath).absolutePath() + QStringLiteral("/workout-vor-update.sqlite");
    QFile::remove(copy);                         // QFile::copy does not overwrite
    if (!QFile::copy(filePath, copy))
        qWarning().noquote() << "Could not copy the database before the update to" << copy;
}

} // namespace

bool Database::open(const QString &filePath)
{
    m_filePath = filePath;
    copyBeforeUpgrade(filePath);
    m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"));
    m_db.setDatabaseName(filePath);
    if (!m_db.open()) {
        m_lastError = m_db.lastError().text();
        qWarning().noquote() << "Could not open the database:" << m_lastError;
        return false;
    }

    // Tables first, then everything that is calculated from them.
    begin();
    upgradeOldTables();
    const bool ready = runScript(QStringLiteral(":/sql/schema.sql"))
                    && runScript(QStringLiteral(":/sql/derived.sql"));
    if (!ready) {
        rollback();
        return false;
    }
    commit();

    // This file now has the tables of this version (see kDataVersion above).
    QSqlQuery stamp(m_db);
    stamp.exec(QStringLiteral("PRAGMA user_version = %1").arg(kDataVersion));

    loadBlocks(readResource(QStringLiteral(":/sql/statements.sql")));

    // Fill the calculated tables from whatever was imported earlier.
    begin();
    const bool filled = runBlock(QStringLiteral("refresh")) && runBlock(QStringLiteral("apply_filter"));
    commit();
    return filled;
}

QString Database::readResource(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning().noquote() << "Missing resource file:" << path;
        return QString();
    }
    return QString::fromUtf8(file.readAll());
}

// Remove "-- comments", then cut the text at every semicolon.
// This is deliberately simple. It works because the .sql files of this app
// never have a semicolon or a double dash inside a text in quotes.
QStringList Database::splitStatements(const QString &script)
{
    QString clean;
    const QStringList lines = script.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        const qsizetype comment = line.indexOf(QStringLiteral("--"));
        clean += (comment >= 0 ? line.left(comment) : line);
        clean += QLatin1Char('\n');
    }

    QStringList statements;
    const QStringList parts = clean.split(QLatin1Char(';'));
    for (const QString &part : parts) {
        const QString statement = part.trimmed();
        if (!statement.isEmpty())
            statements.append(statement);
    }
    return statements;
}

// A database made by an older version of this app lacks a few columns. Each
// one is simply added; where it exists already (or the table does not exist
// yet, on the first start) the statement fails, which is fine.
// When the muscle table is old, it is emptied, so schema.sql fills it again
// with all 23 muscle groups, their German names and their own targets.
void Database::upgradeOldTables()
{
    static const char *columns[] = {
        "ALTER TABLE state ADD COLUMN level TEXT NOT NULL DEFAULT 'intermediate'",
        "ALTER TABLE exercises ADD COLUMN compound INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE exercises ADD COLUMN load_mode TEXT NOT NULL DEFAULT 'total'",
        "ALTER TABLE exercises ADD COLUMN unit TEXT NOT NULL DEFAULT 'reps'",
        "ALTER TABLE workout_exercises ADD COLUMN superset_group TEXT",
        "ALTER TABLE workout_exercises ADD COLUMN target_reps_min INTEGER",
        "ALTER TABLE workout_exercises ADD COLUMN target_reps_max INTEGER",
        "ALTER TABLE sets ADD COLUMN reps_left INTEGER",
        "ALTER TABLE sets ADD COLUMN partials INTEGER",
        "ALTER TABLE muscles ADD COLUMN base_max REAL NOT NULL DEFAULT 20",
    };
    for (const char *sql : columns) {
        QSqlQuery query(m_db);
        query.exec(QString::fromLatin1(sql));       // failing is fine, see above
    }
    QSqlQuery query(m_db);
    if (query.exec(QStringLiteral("ALTER TABLE muscles ADD COLUMN base_min REAL NOT NULL DEFAULT 10"))) {
        QSqlQuery clear(m_db);
        clear.exec(QStringLiteral("DELETE FROM muscles"));
    }

    // "forearms" was split into brachioradialis, forearm flexors and extensors.
    // Old mappings move to the flexors (mostly grip work); the next export of the
    // phone brings the detailed mapping of every exercise anyway.
    static const char *forearms[] = {
        "UPDATE OR IGNORE exercise_muscles SET muscle_id = 'forearm_flexors' WHERE muscle_id = 'forearms'",
        "DELETE FROM exercise_muscles WHERE muscle_id = 'forearms'",
        "DELETE FROM muscles WHERE EXISTS (SELECT 1 FROM muscles WHERE id = 'forearms')",
    };
    for (const char *sql : forearms) {
        QSqlQuery step(m_db);
        step.exec(QString::fromLatin1(sql));        // fails harmlessly on a new database
    }
}

bool Database::runScript(const QString &resourcePath)
{
    const QStringList statements = splitStatements(readResource(resourcePath));
    if (statements.isEmpty()) {
        m_lastError = QStringLiteral("Empty or missing SQL file: ") + resourcePath;
        return false;
    }
    for (const QString &statement : statements) {
        if (!exec(statement))
            return false;
    }
    return true;
}

// statements.sql is cut into blocks at every line "-- name: something".
void Database::loadBlocks(const QString &script)
{
    m_blocks.clear();
    const QString marker = QStringLiteral("-- name:");

    QStringList allLines = script.split(QLatin1Char('\n'));
    allLines.append(marker + QStringLiteral(" (end)"));   // so the loop also stores the last block

    QString name;
    QStringList lines;
    for (const QString &line : std::as_const(allLines)) {
        const QString trimmed = line.trimmed();
        if (trimmed.startsWith(marker)) {
            if (!name.isEmpty())
                m_blocks.insert(name, splitStatements(lines.join(QLatin1Char('\n'))));
            name = trimmed.mid(marker.size()).trimmed();
            lines.clear();
        } else {
            lines.append(line);
        }
    }
}

// Prepare a statement and fill in its :placeholders from the map.
// A placeholder that is not in the map becomes NULL.
bool Database::prepare(QSqlQuery &query, const QString &sql, const QVariantMap &values)
{
    if (!query.prepare(sql)) {
        m_lastError = query.lastError().text() + QStringLiteral("\nSQL: ") + sql.left(300);
        qWarning().noquote() << "SQL error:" << m_lastError;
        return false;
    }

    static const QRegularExpression placeholder(QStringLiteral(":([a-z_]+)"));
    QSet<QString> done;
    QRegularExpressionMatchIterator matches = placeholder.globalMatch(sql);
    while (matches.hasNext()) {
        const QString name = matches.next().captured(1);
        if (done.contains(name))
            continue;
        done.insert(name);
        query.bindValue(QStringLiteral(":") + name, values.value(name));
    }
    return true;
}

bool Database::exec(const QString &sql, const QVariantMap &values)
{
    QSqlQuery query(m_db);
    if (!prepare(query, sql, values))
        return false;
    if (!query.exec()) {
        m_lastError = query.lastError().text() + QStringLiteral("\nSQL: ") + sql.left(300);
        qWarning().noquote() << "SQL error:" << m_lastError;
        return false;
    }
    return true;
}

bool Database::runBlock(const QString &name, const QVariantMap &values)
{
    const auto block = m_blocks.constFind(name);
    if (block == m_blocks.constEnd()) {
        m_lastError = QStringLiteral("Unknown SQL block: ") + name;
        qWarning().noquote() << m_lastError;
        return false;
    }
    for (const QString &statement : block.value()) {
        if (!exec(statement, values))
            return false;
    }
    return true;
}

QVariantList Database::select(const QString &sql, const QVariantMap &values)
{
    QVariantList rows;
    QSqlQuery query(m_db);
    if (!prepare(query, sql, values))
        return rows;
    if (!query.exec()) {
        m_lastError = query.lastError().text() + QStringLiteral("\nSQL: ") + sql.left(300);
        qWarning().noquote() << "SQL error:" << m_lastError;
        return rows;
    }

    const QSqlRecord record = query.record();
    while (query.next()) {
        QVariantMap row;
        for (int column = 0; column < record.count(); ++column) {
            const QVariant cell = query.value(column);
            // SQL NULL becomes "undefined" in QML, which is easy to test for there.
            row.insert(record.fieldName(column), cell.isNull() ? QVariant() : cell);
        }
        rows.append(row);
    }
    return rows;
}

QVariant Database::value(const QString &sql, const QVariantMap &values)
{
    QSqlQuery query(m_db);
    if (!prepare(query, sql, values) || !query.exec() || !query.next())
        return QVariant();
    const QVariant cell = query.value(0);
    return cell.isNull() ? QVariant() : cell;
}

bool Database::begin()
{
    return m_db.transaction();
}

bool Database::commit()
{
    return m_db.commit();
}

void Database::rollback()
{
    m_db.rollback();
}
