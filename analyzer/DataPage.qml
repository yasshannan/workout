import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Workout

// Data : get workouts in (by hand or automatically from a folder), and a full
// backup back out for the phone.
DashPage {
    id: page
    minimumHeight: 600

    property var log: []                           // rows of v_import_log
    property var lastSummary: []                   // what the last import did
    property string message: ""

    function describe(summary) {
        var lines = []
        for (var i = 0; i < summary.length; i++) {
            var s = summary[i]
            lines.push(s.ok ? s.file + ": " + s.added + " neu, " + s.updated + " aktualisiert, " + s.unchanged + " schon bekannt"
                            : s.file + ": " + s.message)
        }
        return lines.join("\n")
    }

    onRefresh: log = backend.rows("v_import_log")

    Connections {
        target: backend
        function onAutoImported(summary) {
            page.message = "Aus dem Ordner importiert:\n" + page.describe(summary)
        }
    }

    FileDialog {
        id: openDialog
        title: "Export-Dateien der Handy-App wählen"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Trainings-Export (*.json)"]
        onAccepted: page.message = page.describe(backend.importFiles(selectedFiles))
    }
    FolderDialog {
        id: folderDialog
        title: "Ordner wählen, in den das Handy seine Exporte speichert"
        onAccepted: {
            backend.setImportFolder(selectedFolder)
            page.message = "Watching " + backend.importFolder
        }
    }
    FileDialog {
        id: backupDialog
        title: "Vollständige Sicherung speichern"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["Trainings-Export (*.json)"]
        onAccepted: page.message = backend.exportBackup(selectedFile)
                    ? "Sicherung gespeichert. Am Handy importieren: Export / Import → Sicherungsdatei importieren."
                    : "Die Sicherung konnte nicht gespeichert werden: " + backend.lastError
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 210
                title: "Automatischer Import"
                note: backend.importFolder !== "" ? "an" : "aus"
                Column {
                    anchors.fill: parent
                    spacing: 10
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.text
                        font.pixelSize: 13
                        text: backend.importFolder !== ""
                              ? "Beobachtet: " + backend.importFolder + "\nJeder neue Export in diesem Ordner wird von selbst importiert, auch beim Start der App."
                              : "Wähle einen Ordner, in den das Handy speichern kann, z. B. einen OneDrive-Ordner. "
                                + "Am Handy: Exportieren → Datei teilen / speichern → OneDrive (oder Dateien) → dieser Ordner. "
                                + "Diese App holt die Datei dann von selbst ab."
                    }
                    Row {
                        spacing: 8
                        AppButton { text: backend.importFolder !== "" ? "Ordner ändern" : "Ordner wählen"; onClicked: folderDialog.open() }
                        AppButton { secondary: true; visible: backend.importFolder !== ""; text: "Jetzt prüfen"
                            onClicked: { var r = backend.scanImportFolder(); page.message = r.length ? page.describe(r) : "Keine neuen Dateien im Ordner." } }
                        AppButton { secondary: true; visible: backend.importFolder !== ""; text: "Ausschalten"
                            onClicked: { backend.setImportFolder(""); page.message = "Der automatische Import ist aus." } }
                    }
                }
            }

            Card {
                Layout.preferredWidth: 360
                Layout.preferredHeight: 210
                title: "Von Hand"
                Column {
                    anchors.fill: parent
                    spacing: 10
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.text
                        font.pixelSize: 13
                        text: "Eine oder mehrere Export-Dateien importieren. Nichts wird doppelt angelegt, zweimal importieren schadet also nicht."
                    }
                    AppButton { text: "Dateien importieren…"; onClicked: openDialog.open() }
                    AppButton { secondary: true; text: "Vollständige Sicherung fürs Handy speichern…"; onClicked: backupDialog.open() }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: page.message !== ""
            implicitHeight: msg.implicitHeight + 20
            radius: Theme.radius
            color: Theme.alpha(Theme.ok, 0.14)
            Text {
                id: msg
                x: 12; y: 10
                width: parent.width - 24
                text: page.message
                color: Theme.text
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "Importierte Dateien"
            note: "neueste zuerst · Datenbank: " + backend.databasePath

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: page.log
                ScrollBar.vertical: ScrollBar { }
                delegate: Item {
                    width: list.width - 10
                    height: 28
                    Text {
                        width: parent.width * 0.45
                        text: modelData.file_name
                        color: Theme.text
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                    }
                    Text {
                        x: parent.width * 0.47
                        text: "exportiert am " + Theme.dayYear((modelData.exported_at || "").substring(0, 10)) + " (" + (modelData.export_type === "full" ? "vollständig" : "seit dem letzten Export") + ")"
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                    Text {
                        anchors.right: parent.right
                        text: modelData.added + " neu · " + modelData.updated + " aktualisiert · " + modelData.unchanged + " bekannt"
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
                Text {
                    visible: page.log.length === 0
                    anchors.centerIn: parent
                    text: "Noch nichts importiert. Probier shared/sample-data.json aus dem Projektordner."
                    color: Theme.muted
                    font.pixelSize: 13
                }
            }
        }
    }
}
