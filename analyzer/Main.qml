import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import Workout

// Main : the window. Sidebar on the left, filter bar on top, one page below.
// The look comes from the original Main.qml of this project: the four greys,
// the inverted light/dark button with 8 px corners, two panes side by side.
ApplicationWindow {
    id: window

    width: 1360
    height: 860
    minimumWidth: 1100
    minimumHeight: 700
    visible: true
    title: qsTr("Trainings-Analyse")
    color: Theme.bg

    property int current: 0
    readonly property var pageNames: ["Übersicht", "Muskeln", "Übungen", "Körper", "Einheiten", "Regelmäßigkeit", "Diagramme", "Erkenntnisse", "Daten", "Einstellungen"]
    // where the pages are in that list (used below, so a new page means one change here)
    readonly property int insightsPage: 7
    readonly property int dataPage: 8

    // Read the saved display options once at start.
    Component.onCompleted: {
        var s = backend.row("v_state")
        Theme.mode = s.theme || "auto"
        Theme.animations = s.animations !== 0
        // A fresh database: start on the Data page, so the first import is one click away.
        if (!s.all_workouts)
            current = dataPage
    }
    // Follow the light/dark setting of Windows (like in the original Main.qml).
    Binding {
        target: Theme
        property: "systemLight"
        value: Application.styleHints.colorScheme !== Qt.Dark
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- sidebar ----------------
        Rectangle {
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            color: Theme.surface
            Behavior on color { ColorAnimation { duration: Theme.normal } }

            Text {
                x: 24; y: 22
                text: "Training"
                color: Theme.text
                font.pixelSize: 24
                font.weight: Font.Bold
            }
            Text {
                x: 24; y: 54
                text: "Analyse"
                color: Theme.muted
                font.pixelSize: 13
            }

            // The highlight slides to the chosen entry.
            Rectangle {
                x: 10
                width: parent.width - 20
                height: 40
                y: nav.y + window.current * 40
                radius: Theme.radius
                color: Theme.text
                Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            }
            Column {
                id: nav
                y: 96
                width: parent.width
                Repeater {
                    model: window.pageNames
                    NavButton {
                        text: modelData
                        current: window.current === index
                        onClicked: window.current = index
                    }
                }
            }

            // The light/dark button of the original Main.qml.
            AppButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                text: Theme.lightMode ? "☽  Dunkel" : "☼  Hell"
                onClicked: {
                    Theme.mode = Theme.lightMode ? "dark" : "light"
                    backend.setOption("theme", Theme.mode)
                }
            }
        }

        // ---------------- filter bar and page ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 16

            FilterBar {
                Layout.fillWidth: true
                visible: window.current < window.dataPage      // Data and Settings need no filters
                onSavePng: pngDialog.open()
                onSavePdf: pdfDialog.open()
            }

            Item {
                id: pageArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                OverviewPage { id: overview; anchors.fill: parent; visible: active; active: window.current === 0
                               onShowInsights: window.current = window.insightsPage }
                MusclesPage { id: muscles; anchors.fill: parent; visible: active; active: window.current === 1 }
                StrengthPage { id: exercises; anchors.fill: parent; visible: active; active: window.current === 2 }
                BodyWeightPage { id: bodyweight; anchors.fill: parent; visible: active; active: window.current === 3 }
                SessionsPage { id: sessions; anchors.fill: parent; visible: active; active: window.current === 4 }
                ConsistencyPage { id: consistency; anchors.fill: parent; visible: active; active: window.current === 5 }
                ChartsPage { id: charts; anchors.fill: parent; visible: active; active: window.current === 6 }
                InsightsPage { id: insights; anchors.fill: parent; visible: active; active: window.current === window.insightsPage }
                DataPage { id: data; anchors.fill: parent; visible: active; active: window.current === window.dataPage }
                SettingsPage { id: settings; anchors.fill: parent; visible: active; active: window.current === 9 }
            }
        }
    }

    // ---------------- messages ----------------
    Rectangle {
        id: toast
        property string text: ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: text === "" ? -height : 18
        width: Math.min(640, toastText.implicitWidth + 32)
        height: toastText.implicitHeight + 20
        radius: Theme.radius
        color: Theme.text
        z: 100
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Text { id: toastText; anchors.centerIn: parent; width: Math.min(608, implicitWidth); text: toast.text
               color: Theme.surface; font.pixelSize: 13; wrapMode: Text.WordWrap }
        Timer { id: toastTimer; interval: 4000; onTriggered: toast.text = "" }
        function show(message) { text = message; toastTimer.restart() }
    }
    Connections {
        target: backend
        function onAutoImported(summary) {
            var n = 0
            for (var i = 0; i < summary.length; i++) if (summary[i].ok) n++
            toast.show(n + (n === 1 ? " neue Export-Datei automatisch importiert." : " neue Export-Dateien automatisch importiert."))
        }
    }

    // ---------------- PNG and PDF ----------------
    FileDialog {
        id: pngDialog
        title: "Diese Seite als Bild speichern"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "png"
        nameFilters: ["PNG-Bild (*.png)"]
        onAccepted: exporter.savePng(pageArea, selectedFile)
    }
    FileDialog {
        id: pdfDialog
        title: "PDF-Bericht speichern"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF-Bericht (*.pdf)"]
        onAccepted: report.start(selectedFile)
    }

    // The PDF report: first the insights as text, then a picture of each page.
    // Animations are switched off while the pictures are taken, so nothing is
    // caught half-way.
    QtObject {
        id: report
        property var queue: []
        property int returnTo: 0
        property bool animationsBefore: true

        function start(file) {
            var s = backend.row("v_state")
            var subtitle = (s.from_day ? Theme.dayYear(s.from_day) : "Beginn") + " – " + Theme.dayYear(s.end_day)
            if (!exporter.beginPdf(file, "Trainingsbericht", subtitle)) {
                toast.show("Das PDF konnte nicht geschrieben werden.")
                return
            }
            var texts = backend.rows("v_insights").map(function (i) {
                return (i.severity === "warn" ? "▲ " : i.severity === "good" ? "✓ " : "• ") + i.text
                       + "\n" + i.reason + (i.source ? "\nQuelle: " + i.source : "")
                       + "\nSicherheit: " + i.confidence
            })
            exporter.addTextPage("Erkenntnisse", texts)
            returnTo = window.current
            animationsBefore = Theme.animations
            Theme.animations = false
            queue = [0, 1, 2, 3, 4, 5]
            next()
        }
        function next() {
            if (queue.length === 0) {
                exporter.endPdf()
                return
            }
            window.current = queue[0]
            grabDelay.restart()                     // give the page a moment to draw itself
        }
    }
    Timer {
        id: grabDelay
        interval: 250
        onTriggered: exporter.addItemPage(pageArea, window.pageNames[report.queue[0]])
    }
    Connections {
        target: exporter
        function onPageAdded() {
            report.queue = report.queue.slice(1)
            report.next()
        }
        function onPdfFinished(ok, path) {
            Theme.animations = report.animationsBefore
            window.current = report.returnTo
            toast.show(ok ? "PDF gespeichert: " + path : "Das PDF konnte nicht geschrieben werden.")
        }
        function onPngSaved(ok, path) {
            toast.show(ok ? "Bild gespeichert: " + path : "Das Bild konnte nicht gespeichert werden.")
        }
    }
}
