import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Workout

// FilterBar : date range, exercise and muscle filter, and the export buttons.
// It only tells the backend what was chosen. The backend then raises
// "revision", and every page (and this bar) reloads.
Rectangle {
    id: bar

    signal savePng()
    signal savePdf()

    property var info: ({})                        // the row of v_state
    property var exercises: []
    property var muscles: []
    readonly property var presets: [
        { id: "4w", text: "4 Wochen" }, { id: "8w", text: "8 Wochen" }, { id: "12w", text: "12 Wochen" },
        { id: "26w", text: "6 Monate" }, { id: "52w", text: "1 Jahr" }, { id: "all", text: "Alles" }
    ]

    function indexOfId(list, id) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return i
        }
        return 0
    }

    function reload() {
        info = backend.row("v_state")
        exercises = [{ id: "", name: "Alle Übungen" }].concat(backend.rows("v_filter_exercises"))
        muscles = [{ id: "", name: "Alle Muskeln" }].concat(backend.rows("v_muscle_list"))
        exerciseBox.currentIndex = indexOfId(exercises, info.exercise_id)
        muscleBox.currentIndex = indexOfId(muscles, info.muscle_id)
        var custom = info.range_preset === "custom"
        fromField.text = custom && info.from_day ? info.from_day : ""
        toField.text = custom && info.to_day ? info.to_day : ""
    }

    // Dates are typed as YYYY-MM-DD. An empty field means "no limit".
    function applyCustomRange() {
        var pattern = /^\d{4}-\d{2}-\d{2}$/
        var fromOk = fromField.text === "" || pattern.test(fromField.text)
        var toOk = toField.text === "" || pattern.test(toField.text)
        if (fromOk && toOk && (fromField.text !== "" || toField.text !== ""))
            backend.setCustomRange(fromField.text, toField.text)
    }

    implicitHeight: 96
    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.normal } }

    Component.onCompleted: reload()
    Connections {
        target: backend
        function onRevisionChanged() {
            bar.reload()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // Row 1: the date range.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: bar.presets
                Chip {
                    text: modelData.text
                    checked: bar.info.range_preset === modelData.id
                    onClicked: backend.setRange(modelData.id)
                }
            }
            Item { implicitWidth: 10 }
            DateField {
                id: fromField
                placeholderText: "von JJJJ-MM-TT"
                onEditingFinished: bar.applyCustomRange()
            }
            DateField {
                id: toField
                placeholderText: "bis JJJJ-MM-TT"
                onEditingFinished: bar.applyCustomRange()
            }
            Item { Layout.fillWidth: true }
            Text {
                text: bar.info.known_until ? "Daten bis " + Theme.dayYear(bar.info.known_until) : "Noch keine Daten"
                color: Theme.muted
                font.pixelSize: 12
            }
        }

        // Row 2: exercise and muscle filter, export buttons.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ComboBox {
                id: exerciseBox
                Layout.preferredWidth: 230
                implicitHeight: 32
                font.pixelSize: 13
                model: bar.exercises
                textRole: "name"
                onActivated: (index) => { backend.setFilter("exercise_id", bar.exercises[index].id) }
            }
            ComboBox {
                id: muscleBox
                Layout.preferredWidth: 160
                implicitHeight: 32
                font.pixelSize: 13
                model: bar.muscles
                textRole: "name"
                onActivated: (index) => { backend.setFilter("muscle_id", bar.muscles[index].id) }
            }
            Chip {
                text: "Filter zurücksetzen"
                onClicked: backend.resetFilters()
            }
            Item { Layout.fillWidth: true }
            AppButton {
                secondary: true
                text: "Seite als PNG"
                implicitHeight: 32
                onClicked: bar.savePng()
            }
            AppButton {
                text: "PDF-Bericht"
                implicitHeight: 32
                onClicked: bar.savePdf()
            }
        }
    }
}
