#include "Importer.h"

#include "Database.h"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QVariant>
#include <QtGlobal>

// The newest file format this app understands (see shared/SCHEMA.md).
static const int kSchemaVersion = 1;

// JSON null (or a missing field) becomes SQL NULL, everything else its plain value.
// Muscle ids of older versions mapped to today's: "forearms" was split into
// brachioradialis, forearm flexors and extensors; old files mean grip work.
static QString currentMuscleId(const QString &id)
{
    return id == QLatin1String("forearms") ? QStringLiteral("forearm_flexors") : id;
}

static QVariant orNull(const QJsonValue &value)
{
    if (value.isNull() || value.isUndefined())
        return QVariant();
    return value.toVariant();
}

// A JSON object as compact text, for the raw_json columns.
static QString toText(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

static QJsonObject fromText(const QString &text)
{
    return QJsonDocument::fromJson(text.toUtf8()).object();
}

// The current time the way the phone writes it: 2026-11-16T21:18:00.000Z
static QString nowIso()
{
    return QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
}

// The merge rule. It is the same on the phone, and it is what prevents duplicates:
//   unknown id                     -> add the record
//   known id, file copy is newer   -> replace our copy
//   known id, file copy is older   -> keep our copy
// "Newer" is decided by the updatedAt text. Because all times are written in
// the same UTC format, comparing the texts compares the times.
bool Importer::needsWrite(const QString &table, const QJsonObject &record, ImportResult &result)
{
    const QString id = record.value("id").toString();
    if (id.isEmpty())
        return false;
    const QVariant stored = m_db.value("SELECT updated_at FROM " + table + " WHERE id = :id", { {"id", id} });
    if (!stored.isValid()) {
        ++result.added;
        return true;
    }
    if (record.value("updatedAt").toString() > stored.toString()) {
        ++result.updated;
        return true;
    }
    ++result.unchanged;
    return false;
}

bool Importer::storeExercise(const QJsonObject &o)
{
    const QString id = o.value("id").toString();
    bool ok = m_db.runBlock("upsert_exercise", {
        {"id", id},
        {"name", o.value("name").toString()},
        {"movement", orNull(o.value("movement"))},
        {"equipment", orNull(o.value("equipment"))},
        {"load_type", o.value("loadType").toString("external")},
        {"bodyweight_fraction", orNull(o.value("bodyweightFraction"))},
        {"compound", o.value("compound").toBool(true) ? 1 : 0},
        {"load_mode", o.value("load").toString("total")},
        {"unit", o.value("unit").toString("reps")},
        {"is_custom", o.value("isCustom").toBool() ? 1 : 0},
        {"updated_at", o.value("updatedAt").toString()},
        {"deleted_at", orNull(o.value("deletedAt"))},
        {"raw_json", toText(o)}
    });

    // Rewrite the muscle mapping of this exercise. A secondary muscle counts with
    // the exercise's own share (muscleShares), ½ if it has none.
    // Files of older versions say "forearms": that is read as forearm flexors.
    ok = m_db.runBlock("clear_exercise_muscles", { {"id", id} }) && ok;
    const QJsonObject shares = o.value("muscleShares").toObject();
    const QJsonArray secondary = o.value("secondaryMuscles").toArray();
    for (const QJsonValue &muscle : secondary) {
        ok = m_db.runBlock("insert_exercise_muscle", {
            {"exercise_id", id},
            {"muscle_id", currentMuscleId(muscle.toString())},
            {"role", QStringLiteral("secondary")},
            {"weight", shares.value(muscle.toString()).toDouble(0.5)}
        }) && ok;
    }
    // Primary muscles are written last, so "primary" wins if a muscle is in both lists.
    const QJsonArray primary = o.value("primaryMuscles").toArray();
    for (const QJsonValue &muscle : primary) {
        ok = m_db.runBlock("insert_exercise_muscle", {
            {"exercise_id", id},
            {"muscle_id", currentMuscleId(muscle.toString())},
            {"role", QStringLiteral("primary")},
            {"weight", 1.0}
        }) && ok;
    }
    return ok;
}

// A workout is always replaced as a whole: its old exercises and sets are
// removed first, then everything from the file is written.
bool Importer::storeWorkout(const QJsonObject &o)
{
    const QString workoutId = o.value("id").toString();
    bool ok = m_db.runBlock("clear_workout", { {"id", workoutId} });
    ok = m_db.runBlock("upsert_workout", {
        {"id", workoutId},
        {"name", orNull(o.value("name"))},
        {"started_at", o.value("startedAt").toString()},
        {"finished_at", orNull(o.value("finishedAt"))},
        {"utc_offset_min", o.value("utcOffsetMin").toInt()},
        {"notes", orNull(o.value("notes"))},
        {"updated_at", o.value("updatedAt").toString()},
        {"deleted_at", orNull(o.value("deletedAt"))},
        {"raw_json", toText(o)}
    }) && ok;

    const QJsonArray entries = o.value("exercises").toArray();
    for (const QJsonValue &entryValue : entries) {
        const QJsonObject entry = entryValue.toObject();
        const QString entryId = entry.value("id").toString();
        ok = m_db.runBlock("insert_entry", {
            {"id", entryId},
            {"workout_id", workoutId},
            {"exercise_id", entry.value("exerciseId").toString()},
            {"sort_order", entry.value("order").toInt()},
            {"notes", orNull(entry.value("notes"))},
            {"superset_group", orNull(entry.value("supersetGroup"))},
            {"target_reps_min", orNull(entry.value("targetRepsMin"))},
            {"target_reps_max", orNull(entry.value("targetRepsMax"))}
        }) && ok;

        const QJsonArray sets = entry.value("sets").toArray();
        for (const QJsonValue &setValue : sets) {
            const QJsonObject set = setValue.toObject();
            ok = m_db.runBlock("insert_set", {
                {"id", set.value("id").toString()},
                {"workout_id", workoutId},
                {"entry_id", entryId},
                {"sort_order", set.value("order").toInt()},
                {"type", set.value("type").toString("work")},
                {"weight_kg", set.value("weightKg").toDouble()},
                {"reps", set.value("reps").toInt()},
                {"reps_left", orNull(set.value("repsLeft"))},
                {"partials", orNull(set.value("partials"))},
                {"rpe", orNull(set.value("rpe"))},
                {"started_at", orNull(set.value("startedAt"))},
                {"completed_at", orNull(set.value("completedAt"))},
                {"target_rest_sec", orNull(set.value("targetRestSec"))}
            }) && ok;
        }
    }
    return ok;
}

ImportResult Importer::importFile(const QString &path)
{
    ImportResult result;
    result.fileName = QFileInfo(path).fileName();

    // 1. Read and check the file.
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        result.message = QStringLiteral("Die Datei konnte nicht geöffnet werden.");
        return result;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        result.message = QStringLiteral("Diese Datei ist keine gültige JSON-Datei.");
        return result;
    }
    const QJsonObject data = document.object();
    if (data.value("app").toString() != QLatin1String("workout-tracker")) {
        result.message = QStringLiteral("Das ist keine Export-Datei der Trainings-App.");
        return result;
    }
    const int version = data.value("schemaVersion").toInt();
    if (version < 1) {
        result.message = QStringLiteral("Die Datei hat keine gültige schemaVersion.");
        return result;
    }
    if (version > kSchemaVersion) {
        result.message = QStringLiteral("Die Datei hat Formatversion %1, diese App kennt nur Version %2. Bitte zuerst die App aktualisieren.")
                             .arg(version).arg(kSchemaVersion);
        return result;
    }
    // If the format ever changes, older files are upgraded here, step by step,
    // before anything is stored (see "Changing the format later" in SCHEMA.md).
    const QStringList lists = { "exercises", "templates", "workouts", "bodyWeights" };
    for (const QString &list : lists) {
        if (!data.value(list).isArray()) {
            result.message = QStringLiteral("Die Datei ist beschädigt: \"%1\" fehlt.").arg(list);
            return result;
        }
    }

    // 2. Merge it. Everything happens in one transaction: either the whole
    //    file is imported, or (if something fails) nothing is.
    m_db.begin();
    bool ok = true;

    const QJsonArray exercises = data.value("exercises").toArray();
    for (const QJsonValue &item : exercises) {
        const QJsonObject o = item.toObject();
        if (needsWrite("exercises", o, result))
            ok = storeExercise(o) && ok;
    }

    const QJsonArray templates = data.value("templates").toArray();
    for (const QJsonValue &item : templates) {
        const QJsonObject o = item.toObject();
        if (needsWrite("templates", o, result)) {
            ok = m_db.runBlock("upsert_template", {
                {"id", o.value("id").toString()},
                {"name", orNull(o.value("name"))},
                {"updated_at", o.value("updatedAt").toString()},
                {"deleted_at", orNull(o.value("deletedAt"))},
                {"raw_json", toText(o)}
            }) && ok;
        }
    }

    const QJsonArray workouts = data.value("workouts").toArray();
    for (const QJsonValue &item : workouts) {
        const QJsonObject o = item.toObject();
        if (needsWrite("workouts", o, result))
            ok = storeWorkout(o) && ok;
    }

    const QJsonArray bodyWeights = data.value("bodyWeights").toArray();
    for (const QJsonValue &item : bodyWeights) {
        const QJsonObject o = item.toObject();
        if (needsWrite("body_weights", o, result)) {
            ok = m_db.runBlock("upsert_body_weight", {
                {"id", o.value("id").toString()},
                {"measured_at", o.value("measuredAt").toString()},
                {"weight_kg", o.value("weightKg").toDouble()},
                {"updated_at", o.value("updatedAt").toString()},
                {"deleted_at", orNull(o.value("deletedAt"))},
                {"raw_json", toText(o)}
            }) && ok;
        }
    }

    // Body measurements (optional: older files have none).
    const QJsonArray measurements = data.value("measurements").toArray();
    for (const QJsonValue &item : measurements) {
        const QJsonObject o = item.toObject();
        if (needsWrite("measurements", o, result)) {
            ok = m_db.runBlock("upsert_measurement", {
                {"id", o.value("id").toString()},
                {"measured_at", o.value("measuredAt").toString()},
                {"waist_cm", orNull(o.value("waistCm"))},
                {"chest_cm", orNull(o.value("chestCm"))},
                {"arm_cm", orNull(o.value("armCm"))},
                {"thigh_cm", orNull(o.value("thighCm"))},
                {"calf_cm", orNull(o.value("calfCm"))},
                {"body_fat_pct", orNull(o.value("bodyFatPct"))},
                {"updated_at", o.value("updatedAt").toString()},
                {"deleted_at", orNull(o.value("deletedAt"))},
                {"raw_json", toText(o)}
            }) && ok;
        }
    }

    const QString exportedAt = data.value("exportedAt").toString();
    ok = m_db.runBlock("save_meta", {
        {"key", QStringLiteral("settings")},
        {"value", toText(data.value("settings").toObject())}
    }) && ok;
    ok = m_db.runBlock("note_export", { {"exported_at", exportedAt} }) && ok;
    ok = m_db.runBlock("log_import", {
        {"imported_at", nowIso()},
        {"file_name", result.fileName},
        {"exported_at", exportedAt},
        {"export_type", orNull(data.value("exportType"))},
        {"added", result.added},
        {"updated", result.updated},
        {"unchanged", result.unchanged}
    }) && ok;

    if (!ok) {
        m_db.rollback();
        result.message = QStringLiteral("Die Datenbank hat die Daten abgelehnt: ") + m_db.lastError();
        return result;
    }

    // 3. Recalculate everything that depends on the data.
    ok = m_db.runBlock("refresh");
    m_db.commit();
    if (!ok) {
        result.message = QStringLiteral("Importiert, aber die Statistik konnte nicht neu berechnet werden: ") + m_db.lastError();
        return result;
    }
    result.ok = true;
    return result;
}

QString Importer::writeBackup(const QString &path)
{
    QJsonObject root;
    root["schemaVersion"] = kSchemaVersion;
    root["app"] = QStringLiteral("workout-tracker");
    root["exportedAt"] = nowIso();
    root["exportType"] = QStringLiteral("full");
    root["changedSince"] = QJsonValue(QJsonValue::Null);

    // The phone's settings as they were in the newest imported file.
    QJsonObject settings = fromText(m_db.value("SELECT value FROM meta WHERE key = 'settings'").toString());
    if (settings.isEmpty()) {
        settings["unit"] = QStringLiteral("kg");
        settings["defaultRestSec"] = 120;
        settings["soundOn"] = false;
        settings["keepScreenOn"] = true;
    }
    root["settings"] = settings;

    // Every record is stored with its original JSON, so nothing is lost on the way back.
    const QVariantList exerciseRows = m_db.select("SELECT raw_json FROM exercises ORDER BY name");
    const QVariantList templateRows = m_db.select("SELECT raw_json FROM templates ORDER BY name");
    const QVariantList workoutRows = m_db.select("SELECT raw_json FROM workouts ORDER BY started_at");
    const QVariantList weightRows = m_db.select("SELECT raw_json FROM body_weights ORDER BY measured_at");
    const QVariantList measurementRows = m_db.select("SELECT raw_json FROM measurements ORDER BY measured_at");

    const auto toArray = [](const QVariantList &rows) {
        QJsonArray array;
        for (const QVariant &row : rows)
            array.append(fromText(row.toMap().value("raw_json").toString()));
        return array;
    };
    root["exercises"] = toArray(exerciseRows);
    root["templates"] = toArray(templateRows);
    root["workouts"] = toArray(workoutRows);
    root["bodyWeights"] = toArray(weightRows);
    root["measurements"] = toArray(measurementRows);

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return QStringLiteral("Die Datei konnte nicht geschrieben werden.");
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    return QString();
}

bool Importer::setExerciseMuscles(const QString &exerciseId, const QStringList &primary, const QStringList &secondary,
                                  const QVariantMap &shares)
{
    const QString raw = m_db.value("SELECT raw_json FROM exercises WHERE id = :id", { {"id", exerciseId} }).toString();
    if (raw.isEmpty())
        return false;

    QJsonObject o = fromText(raw);
    o["primaryMuscles"] = QJsonArray::fromStringList(primary);
    o["secondaryMuscles"] = QJsonArray::fromStringList(secondary);
    // only shares that are not the default 0.5 are written, like on the phone
    QJsonObject ownShares;
    for (const QString &muscle : secondary) {
        const double share = shares.value(muscle, 0.5).toDouble();
        if (qAbs(share - 0.5) > 0.001)
            ownShares[muscle] = share;
    }
    if (ownShares.isEmpty())
        o.remove("muscleShares");
    else
        o["muscleShares"] = ownShares;
    o["editedByUser"] = true;              // the phone's library updates leave it alone
    o["updatedAt"] = nowIso();

    m_db.begin();
    const bool ok = storeExercise(o);
    m_db.commit();
    return ok;
}
