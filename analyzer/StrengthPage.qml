import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Workout

// Exercises : everything about one exercise. Pick it in the list on the left.
//
//   * numbers: sessions, sets, reps, kilograms, records, rest
//   * a chart that switches between strength (estimated 1RM for multi-joint
//     exercises, the heaviest weight for isolation exercises), kilograms per
//     workout and hard sets per week; strength can be shown per kg body weight
//   * personal records
//
// GOLD means a record, the same as on the phone:
//   * a gold point on the strength line = best so far
//   * a gold bar in "kg pro Training"  = more kilograms than any workout before
//                                        WITH THE SAME NUMBER OF SETS
//   * a gold exercise in the list      = its latest workout was a volume record
DashPage {
    id: page
    minimumHeight: 760

    property var exercises: []                     // rows of v_exercise_stats
    property var series: []                        // best set per training day (v_strength_series)
    property var sessions: []                      // one row per workout (v_exercise_sessions)
    property var weekly: []                        // v_exercise_weekly
    property var records: []                       // rows of v_prs
    property var detail: ({})                      // row of v_exercise_detail
    property string selected: ""
    property string formula: "epley"
    property string chartMode: "e1rm"              // "e1rm" (strength), "volume" or "sets"
    property bool relative: false                  // strength divided by body weight
    readonly property bool hasE1rm: detail.has_e1rm === 1

    readonly property var current: find(selected)
    readonly property var repRecords: records.filter(function (r) { return r.kind === "reps" })

    function find(id) {
        for (var i = 0; i < exercises.length; i++) {
            if (exercises[i].exercise_id === id)
                return exercises[i]
        }
        return null
    }
    function record(kind) {
        for (var i = 0; i < records.length; i++) {
            if (records[i].kind === kind)
                return records[i]
        }
        return null
    }
    function loadType() {
        return current ? current.load_type : "external"
    }
    function loadMode() {
        return current ? current.load_mode : "total"
    }
    function setText(r) {
        return Theme.setLabel(r.weight_kg, r.reps, page.loadType(), page.loadMode(), current ? current.unit : "reps")
    }
    function isStalled(e) {
        return e.has_e1rm === 1 && e.weeks_since_best >= 4 && e.trained_since_best >= 3
    }
    // The small text at the right of an exercise in the list.
    function trendText(e) {
        if (e.gold)
            return "★ Volumenrekord"
        if (isStalled(e))
            return "seit " + e.weeks_since_best + " Wo. kein Plus"
        if (e.pct_4w === undefined || e.weeks_fit < 3)
            return ""
        var rounded = Math.round(e.pct_4w)
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "") + Math.abs(rounded) + " % / 4 Wo."
    }
    function trendColor(e) {
        if (e.gold)
            return Theme.gold
        if (isStalled(e))
            return Theme.warn
        if (e.pct_4w === undefined || e.weeks_fit < 3)
            return Theme.muted
        return e.pct_4w >= 2 ? Theme.ok : e.pct_4w <= -3 ? Theme.high : Theme.muted
    }
    function loadDetail() {
        backend.select("sel_exercise", selected)
        series = backend.rows("v_strength_series")
        sessions = backend.rows("v_exercise_sessions")
        weekly = backend.rows("v_exercise_weekly")
        records = backend.rows("v_prs")
        detail = backend.row("v_exercise_detail")
    }
    function pick(id) {
        selected = id
        loadDetail()
    }

    onRefresh: {
        formula = backend.row("v_state").formula
        exercises = backend.rows("v_exercise_stats")
        if (find(selected) === null)
            selected = exercises.length > 0 ? exercises[0].exercise_id : ""
        loadDetail()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ---------------- the list of exercises ----------------
        Card {
            Layout.preferredWidth: 320
            Layout.fillHeight: true
            title: "Übungen"
            note: "meist trainierte zuerst"

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: page.exercises
                ScrollBar.vertical: ScrollBar { }

                delegate: Item {
                    width: list.width - 10
                    height: 50

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: modelData.gold ? Theme.alpha(Theme.gold, modelData.exercise_id === page.selected ? 0.3 : 0.14)
                             : modelData.exercise_id === page.selected ? Theme.hover
                             : rowMouse.containsMouse ? Theme.alpha(Theme.text, 0.045) : "transparent"
                        border.width: modelData.gold ? 1 : 0
                        border.color: Theme.gold
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    Text {
                        x: 8
                        y: 7
                        width: parent.width - 16
                        text: modelData.name
                        color: modelData.gold ? Theme.gold : Theme.text
                        font.pixelSize: 13
                        font.weight: modelData.exercise_id === page.selected || modelData.gold ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Text {
                        x: 8
                        y: 27
                        text: Theme.num(modelData.sets, 1).replace(",0", "") + " Sätze" + (modelData.best_e1rm !== undefined
                                  ? " · 1RM " + Theme.weight(modelData.best_e1rm)
                                  : modelData.best_weight !== undefined ? " · max. " + Theme.weight(modelData.best_weight) : "")
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        y: 27
                        text: page.trendText(modelData)
                        color: page.trendColor(modelData)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.pick(modelData.exercise_id)
                    }
                }
            }
        }

        // ---------------- everything about the selected exercise ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: page.current ? page.current.name : "Keine Übung in diesem Zeitraum"
                color: Theme.text
                font.pixelSize: 20
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: page.current !== null
                text: "Trainiert " + (page.detail.primary_names || "–")
                      + (page.detail.secondary_names ? "  ·  nebenbei " + page.detail.secondary_names : "")
                      + (page.detail.first_day ? "  ·  " + Theme.dayYear(page.detail.first_day) + " bis " + Theme.dayYear(page.detail.last_day) : "")
                color: Theme.muted
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 6
                rowSpacing: 10
                columnSpacing: 10

                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Trainings"; value: page.detail.sessions || 0
                    note: Theme.num(page.detail.sets_per_week || 0, 1) + " harte Sätze / Woche" }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Harte Sätze"; value: page.detail.work_sets || 0
                    note: "+ " + (page.detail.warmup_sets || 0) + " Aufwärmsätze"
                          + (page.detail.drop_sets ? ", " + page.detail.drop_sets + " Drop-Teile" : "") }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Wiederholungen"; value: page.detail.total_reps || 0
                    note: "im Schnitt " + Theme.num(page.detail.avg_reps || 0, 1) + " pro Satz" }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Bewegte Kilogramm"; value: (page.detail.volume_kg || 0); suffix: " kg"
                    note: "bestes Training " + Theme.weight(page.detail.best_session_kg || 0, 0) }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "★ Rekorde"; value: (page.detail.volume_prs || 0) + (page.detail.e1rm_prs || 0)
                    note: (page.detail.e1rm_prs || 0) + " Kraft · " + (page.detail.volume_prs || 0) + " Volumen" }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Pro kg Körpergewicht"
                    plainText: page.detail.best_rel !== undefined ? Theme.num(page.detail.best_rel, 2) + " ×" : "–"
                    note: page.detail.best_rel !== undefined
                          ? (page.hasE1rm ? "bestes 1RM ÷ Körpergewicht" : "schwerstes Gewicht ÷ Körpergewicht")
                          : "Körpergewicht am Handy eintragen" }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: page.chartMode === "e1rm"
                       ? (page.hasE1rm ? "Geschätztes 1RM" : "Schwerstes Gewicht")
                         + (page.relative ? " pro kg Körpergewicht" : " (kg)") + ", bester Satz pro Tag"
                     : page.chartMode === "volume" ? "Bewegte Kilogramm pro Training (Gold = mehr als je zuvor bei gleicher Satzzahl)"
                     : "Harte Sätze pro Woche"

                Row {                              // what the chart shows, placed in the title line
                    anchors.right: parent.right
                    y: -40
                    spacing: 6
                    Chip { text: page.hasE1rm ? "1RM" : "Gewicht"; checked: page.chartMode === "e1rm"; onClicked: page.chartMode = "e1rm" }
                    Chip { text: "kg pro Training"; checked: page.chartMode === "volume"; onClicked: page.chartMode = "volume" }
                    Chip { text: "Sätze pro Woche"; checked: page.chartMode === "sets"; onClicked: page.chartMode = "sets" }
                    Item { width: 10; height: 1 }
                    Chip {
                        visible: page.chartMode === "e1rm"
                        text: "÷ Körpergewicht"
                        checked: page.relative
                        onClicked: page.relative = !page.relative
                    }
                    Chip {
                        visible: page.chartMode === "e1rm" && page.hasE1rm
                        text: "Epley"
                        checked: page.formula === "epley"
                        onClicked: backend.setOption("formula", "epley")
                    }
                    Chip {
                        visible: page.chartMode === "e1rm" && page.hasE1rm
                        text: "Brzycki"
                        checked: page.formula === "brzycki"
                        onClicked: backend.setOption("formula", "brzycki")
                    }
                }

                LineChart {
                    anchors.fill: parent
                    visible: page.chartMode === "e1rm"
                    points: page.series.filter(function (s) { return !page.relative || s.rel !== undefined }).map(function (s) {
                        return {
                            x: Theme.dayNumber(s.day),
                            y: page.relative ? s.rel : s.value,
                            label: Theme.day(s.day),
                            gold: s.is_pr === 1,
                            tip: (s.is_pr === 1 ? "★ Rekord! " : "") + Theme.day(s.day) + ": "
                                 + (page.relative ? Theme.num(s.rel, 2) + " × Körpergewicht" : Theme.weight(s.value))
                                 + (page.hasE1rm ? " aus " : " bei ") + page.setText(s)
                        }
                    })
                }
                BarChart {
                    anchors.fill: parent
                    visible: page.chartMode === "volume"
                    model: page.sessions.map(function (s) {
                        return {
                            label: Theme.day(s.day),
                            value: s.volume_kg,
                            gold: s.is_volume_pr === 1,
                            tip: (s.is_volume_pr === 1 ? "★ Volumenrekord! " : "") + Theme.day(s.day) + ": "
                                 + Theme.weight(s.volume_kg, 0) + " in " + Theme.num(s.sets, 1).replace(",0", "") + " Sätzen"
                                 + (s.before_best !== undefined
                                    ? " · erste " + s.compare_sets + " Sätze " + Theme.weight(s.compare_kg, 0)
                                      + " gegen bisher bestes " + Theme.weight(s.before_best, 0) : "")
                        }
                    })
                }
                BarChart {
                    anchors.fill: parent
                    visible: page.chartMode === "sets"
                    model: page.weekly.map(function (w) {
                        return {
                            label: Theme.day(w.week_start),
                            value: w.sets,
                            faded: !w.is_complete,
                            tip: "Woche ab " + Theme.day(w.week_start) + ": " + Theme.num(w.sets, 1).replace(",0", "") + " Sätze, " + Theme.weight(w.volume_kg, 0)
                        }
                    })
                }
                Text {
                    visible: page.chartMode === "e1rm" && page.series.length === 0 && page.exercises.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    text: page.relative ? "Dafür muss am Handy das Körpergewicht eingetragen sein."
                                        : "Ein geschätztes 1RM braucht Arbeitssätze mit höchstens 8 Wiederholungen."
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 168
                spacing: 12

                ColumnLayout {
                    Layout.preferredWidth: 250
                    Layout.fillHeight: true
                    spacing: 10

                    StatTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        label: "Schwerster Satz"
                        plainText: page.record("heaviest") ? page.setText(page.record("heaviest")) : "–"
                        note: page.record("heaviest") ? Theme.dayYear(page.record("heaviest").day) : ""
                    }
                    StatTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        label: "Bestes geschätztes 1RM"
                        value: page.record("e1rm") ? page.record("e1rm").e1rm : 0
                        decimals: 1
                        suffix: " kg"
                        plainText: page.hasE1rm ? "" : "–"
                        note: !page.hasE1rm ? "nur bei Mehrgelenksübungen sinnvoll"
                              : page.record("e1rm")
                                ? page.setText(page.record("e1rm")) + " am " + Theme.dayYear(page.record("e1rm").day)
                                : "keine Sätze mit höchstens 8 Wdh."
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "Meiste Wiederholungen pro Gewicht"
                    note: "schwerste Gewichte zuerst"

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        rowSpacing: 2
                        columnSpacing: 24
                        flow: GridLayout.TopToBottom
                        rows: 4

                        Repeater {
                            model: page.repRecords
                            Row {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    width: 140
                                    text: page.setText(modelData)
                                    color: Theme.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: Theme.dayYear(modelData.day)
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
