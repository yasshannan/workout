import QtQuick
import QtQuick.Layouts
import Workout

// Muscles : weekly hard sets per muscle against the target range, how often
// each muscle is trained, and the push/pull and upper/lower balance.
DashPage {
    id: page
    minimumHeight: 760

    property var muscles: []                       // rows of v_muscles
    property var series: []                        // weekly sets of the selected muscle
    property var balance: []
    property var detail: ({})                      // v_muscle_detail of the selected muscle
    property var contributors: []                  // v_muscle_exercises: which exercises gave the sets
    property string selected: ""                   // id of the selected muscle
    property real grow: 0                          // 0 → 1, makes the bars of the list grow

    readonly property var current: find(selected)
    readonly property real scaleMax: largest() * 1.12

    function find(id) {
        for (var i = 0; i < muscles.length; i++) {
            if (muscles[i].muscle_id === id)
                return muscles[i]
        }
        return null
    }
    function largest() {
        var m = 1
        for (var i = 0; i < muscles.length; i++)
            m = Math.max(m, muscles[i].sets_per_week, muscles[i].target_max)
        return m
    }
    function pair(name) {
        for (var i = 0; i < balance.length; i++) {
            if (balance[i].pair === name)
                return balance[i]
        }
        return { a_label: "", a_value: 0, b_label: "", b_value: 0 }
    }
    function loadSeries() {
        backend.select("sel_muscle", selected)
        series = backend.rows("v_muscle_series")
        detail = backend.row("v_muscle_detail")
        contributors = backend.rows("v_muscle_exercises")
    }
    function pick(id) {
        selected = id
        loadSeries()
    }

    onRefresh: {
        muscles = backend.rows("v_muscles")
        balance = backend.rows("v_balance")
        if (find(selected) === null)
            selected = muscles.length > 0 ? muscles[0].muscle_id : ""
        loadSeries()
        growAnimation.restart()
    }

    NumberAnimation {
        id: growAnimation
        target: page
        property: "grow"
        from: 0
        to: 1
        duration: Theme.slow
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 110
            title: "Harte Sätze pro Woche"
            note: "Sätze · Einheiten pro Woche · Status"

            Item {
                id: listArea
                anchors.fill: parent
                anchors.bottomMargin: 26

                Column {
                    anchors.fill: parent
                    Repeater {
                        model: page.muscles
                        RangeBar {
                            width: parent.width
                            height: Math.max(20, Math.min(38, listArea.height / Math.max(1, page.muscles.length)))
                            name: modelData.name
                            value: modelData.sets_per_week
                            sessions: modelData.sessions_per_week
                            targetMin: modelData.target_min
                            targetMax: modelData.target_max
                            status: modelData.status
                            scaleMax: page.scaleMax
                            t: Theme.stagger(page.grow, index, page.muscles.length)
                            selected: modelData.muscle_id === page.selected
                            onClicked: page.pick(modelData.muscle_id)
                        }
                    }
                }
            }
            Row {                                  // what the parts of a row mean
                anchors.bottom: parent.bottom
                spacing: 8
                Rectangle {
                    width: 22
                    height: 10
                    y: 3
                    color: Theme.alpha(Theme.ok, 0.32)
                }
                Text {
                    text: "Zielbereich     1 Satz = Hauptmuskel, 0,1–0,9 Satz = Nebenmuskel (je nach Übung)"
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 100
            spacing: 12

            // Numbers about the selected muscle.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: (page.detail.name || "Muskel") + ": Sätze / Woche"
                    value: page.detail.sets_per_week || 0; decimals: 1
                    note: "Ziel " + Theme.num(page.detail.target_min || 0) + "–" + Theme.num(page.detail.target_max || 0) }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Trainiert"; value: page.detail.sessions_per_week || 0; decimals: 1; suffix: "× / Woche"
                    note: "beste Woche " + Theme.num(page.detail.best_week_sets || 0, 1) + " Sätze" }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Wochen im Ziel"
                    plainText: (page.detail.weeks_ok || 0) + " von " + ((page.detail.weeks_ok || 0) + (page.detail.weeks_under || 0) + (page.detail.weeks_high || 0))
                    note: (page.detail.weeks_under || 0) + " darunter · " + (page.detail.weeks_high || 0) + " sehr hoch" }
                StatTile { Layout.fillWidth: true; implicitHeight: 82
                    label: "Kilogramm"; value: (page.detail.volume_kg || 0); suffix: " kg"
                    note: (page.detail.exercises || 0) + " Übungen" }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: (page.current ? page.current.name : "Muskel") + ": harte Sätze pro Woche"
                note: "schattiert: Zielbereich"

                BarChart {
                    anchors.fill: parent
                    bandMin: page.current ? page.current.target_min : -1
                    bandMax: page.current ? page.current.target_max : -1
                    model: page.series.map(function (w) {
                        return {
                            label: Theme.day(w.week_start),
                            value: w.sets,
                            faded: !w.is_complete,
                            tip: "Woche ab " + Theme.day(w.week_start) + ": " + Theme.num(w.sets, 1) + " Sätze in "
                                 + w.sessions + (w.sessions === 1 ? " Einheit" : " Einheiten")
                        }
                    })
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 178
                spacing: 12

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "Woher die Sätze kommen"
                    note: "Sätze / Woche"
                    Column {
                        anchors.fill: parent
                        spacing: 3
                        clip: true
                        Repeater {
                            model: page.contributors
                            Item {
                                width: parent.width
                                height: 22
                                Text {
                                    width: parent.width - 120
                                    text: modelData.name + (modelData.role === "secondary"
                                          ? "  (" + Theme.num(modelData.weight, 1) + ")" : "")
                                    color: Theme.text
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Rectangle {                // a small bar for the share
                                    x: parent.width - 112
                                    y: 6
                                    height: 10
                                    radius: 5
                                    width: 70 * modelData.sets_per_week / Math.max(0.1, page.detail.sets_per_week || 0.1)
                                    color: Theme.alpha(Theme.text, modelData.role === "secondary" ? 0.35 : 0.8)
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: Theme.num(modelData.sets_per_week, 1)
                                    color: Theme.text
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        Text {
                            visible: page.contributors.length === 0
                            text: "Keine Übung für diesen Muskel in diesem Zeitraum."
                            color: Theme.muted
                            font.pixelSize: 13
                        }
                    }
                }

                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    title: "Balance"
                    note: "harte Sätze pro Woche"

                    Column {
                        anchors.fill: parent
                        spacing: 14
                        SplitBar {
                            width: parent.width
                            leftLabel: page.pair("push_pull").a_label
                            leftValue: page.pair("push_pull").a_value
                            rightLabel: page.pair("push_pull").b_label
                            rightValue: page.pair("push_pull").b_value
                        }
                        SplitBar {
                            width: parent.width
                            leftLabel: page.pair("upper_lower").a_label
                            leftValue: page.pair("upper_lower").a_value
                            rightLabel: page.pair("upper_lower").b_label
                            rightValue: page.pair("upper_lower").b_value
                        }
                    }
                }
            }
        }
    }
}
