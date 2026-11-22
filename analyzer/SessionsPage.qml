import QtQuick
import QtQuick.Layouts
import Workout

// Sessions : how long workouts take and how long you really rest.
DashPage {
    id: page
    minimumHeight: 640

    property var sessions: []                      // rows of v_sessions
    property var stats: ({})                       // row of v_session_stats
    property var rests: []                         // rows of v_rest_by_exercise

    readonly property var withRest: sessions.filter(function (s) { return s.avg_rest_sec !== undefined })

    onRefresh: {
        sessions = backend.rows("v_sessions")
        stats = backend.row("v_session_stats")
        rests = backend.rows("v_rest_by_exercise")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            StatTile {
                Layout.fillWidth: true
                label: "Trainingsdauer"
                value: page.stats.avg_duration_min || 0
                formatter: function (v) { return Theme.duration(v) }
                note: page.sessions.length + " Trainings"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Pause zwischen Sätzen"
                value: page.stats.avg_rest_sec || 0
                formatter: function (v) { return Theme.clock(v) }
                note: "Arbeitssätze derselben Übung"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Pause zwischen Übungen"
                value: page.stats.avg_pause_sec || 0
                formatter: function (v) { return Theme.clock(v) }
                note: "Gerät wechseln, einstellen"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Dauer eines Satzes"
                value: page.stats.avg_set_sec || 0
                formatter: function (v) { return Theme.clock(v) }
                note: "wo „Satz starten“ getippt wurde"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Trainingsdauer (Minuten)"
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.sessions.map(function (s) {
                        return {
                            x: Theme.dayNumber(s.day),
                            y: s.duration_min,
                            label: Theme.day(s.day),
                            tip: Theme.day(s.day) + " " + (s.name || "Training") + ": " + Theme.duration(s.duration_min)
                                 + ", " + Theme.num(s.work_sets, 1).replace(",0", "") + " Sätze"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Durchschnittliche Pause pro Training (Sekunden)"
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.withRest.map(function (s) {
                        return {
                            x: Theme.dayNumber(s.day),
                            y: s.avg_rest_sec,
                            label: Theme.day(s.day),
                            tip: Theme.day(s.day) + " " + (s.name || "Training") + ": " + Theme.clock(s.avg_rest_sec) + " Pause"
                        }
                    })
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 212
            title: "Pause pro Übung"
            note: "tatsächliche Pause · Ziel am Handy"

            GridLayout {
                anchors.fill: parent
                columns: 2
                rows: 5
                flow: GridLayout.TopToBottom
                rowSpacing: 4
                columnSpacing: 32

                Repeater {
                    model: page.rests
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        Text {
                            width: parent.width - 150
                            text: modelData.name
                            color: Theme.text
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            x: parent.width - 140
                            width: 60
                            horizontalAlignment: Text.AlignRight
                            text: Theme.clock(modelData.avg_rest_sec)
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            x: parent.width - 70
                            width: 70
                            horizontalAlignment: Text.AlignRight
                            text: modelData.avg_target_sec !== undefined ? Theme.clock(modelData.avg_target_sec) : "–"
                            color: Theme.muted
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
