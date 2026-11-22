#pragma once

#include <QHash>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

// Database : a thin wrapper around the SQLite file.
//
// All SQL text lives in the sql/ folder, not in C++:
//   sql/schema.sql      permanent tables            (run at every start)
//   sql/derived.sql     calculated tables and views (rebuilt at every start)
//   sql/statements.sql  named blocks, run with runBlock("name", {values})
//
// Values are passed as a map. For the statement
//     DELETE FROM sets WHERE workout_id = :id
// you write   runBlock("clear_workout", { {"id", someId} })
class Database
{
public:
    // Open (or create) the database file and prepare all tables and views.
    bool open(const QString &filePath);

    // Run every statement of one named block from sql/statements.sql.
    bool runBlock(const QString &name, const QVariantMap &values = {});

    // Run one statement that returns nothing.
    bool exec(const QString &sql, const QVariantMap &values = {});
    void upgradeOldTables();

    // Run a SELECT. Each row becomes a map: column name -> value.
    QVariantList select(const QString &sql, const QVariantMap &values = {});

    // First column of the first row of a SELECT (an invalid QVariant if there is no row).
    QVariant value(const QString &sql, const QVariantMap &values = {});

    // Many changes inside begin() ... commit() are written to disk in one go,
    // which is much faster and keeps the file consistent if something fails.
    bool begin();
    bool commit();
    void rollback();

    QString filePath() const { return m_filePath; }
    QString lastError() const { return m_lastError; }

    // Cut a script into single statements (comments removed).
    static QStringList splitStatements(const QString &script);

private:
    static QString readResource(const QString &path);
    bool runScript(const QString &resourcePath);
    void loadBlocks(const QString &script);
    bool prepare(QSqlQuery &query, const QString &sql, const QVariantMap &values);

    QSqlDatabase m_db;
    QHash<QString, QStringList> m_blocks;   // block name -> its statements
    QString m_filePath;
    QString m_lastError;
};
