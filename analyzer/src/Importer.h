#pragma once

#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class Database;

// What happened when one file was imported.
struct ImportResult
{
    bool ok = false;
    QString fileName;
    QString message;      // the reason, if ok is false
    int added = 0;
    int updated = 0;
    int unchanged = 0;
};

// Importer : reads the phone's export files into the database, and writes a
// full backup file back out. The file format is described in shared/SCHEMA.md.
class Importer
{
public:
    explicit Importer(Database &db) : m_db(db) {}

    // Merge one export file into the database (no duplicates, see needsWrite).
    ImportResult importFile(const QString &path);

    // Write everything in the database as one "full" export file that the
    // phone app can import. Returns an error text, or an empty text on success.
    QString writeBackup(const QString &path);

    // Change which muscles an exercise trains. The change gets a fresh
    // "updatedAt", so it also wins on the phone when it imports a backup.
    bool setExerciseMuscles(const QString &exerciseId, const QStringList &primary, const QStringList &secondary,
                            const QVariantMap &shares);

private:
    bool needsWrite(const QString &table, const QJsonObject &record, ImportResult &result);
    bool storeExercise(const QJsonObject &o);
    bool storeWorkout(const QJsonObject &o);

    Database &m_db;
};
