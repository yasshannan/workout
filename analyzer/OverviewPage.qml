import QtQuick
import QtQuick.Layouts
import Workout

// Overview : the plan for next week first, then the headline numbers and weekly volume.
DashPage {
    id: page
    minimumHeight: 780

    signal showInsights()

    property var totals: ({})
    property var streaks: ({})
    property var weekly: []
    property var plan: []                          // rows of v_next_week

    onRefresh: {
        totals = backend.row("v_totals")
        streaks = backend.row("v_streaks")
        weekly = backend.rows("v_weekly")
        plan = backend.rows("v_next_week")
    }

    function weekName(w) {
        return "Woche ab " + Theme.day(w.week_start) + (w.is_complete ? "" : " (läuft noch)")
    }

    // A sign and a colour for each kind of action in the plan.
    function planSign(kind) {
        return { add: "+", less: "−", up: "↑", stall: "■", balance: "⇄", body: "◎", ok: "✓" }[kind] || "i"
    }
    function planColor(kind) {
        if (kind === "up" || kind === "ok") return Theme.ok
        if (kind === "less") return Theme.high
        if (kind === "info") return Theme.muted
        return Theme.warn
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // ---------- the plan for next week: what to do differently ----------
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(330, 64 + Math.max(1, page.plan.length) * 40)
            title: "Nächste Woche"

            AppButton {
                anchors.right: parent.right
                y: -40
                secondary: true
                implicitHeight: 30
                text: "Alle Erkenntnisse"
                onClicked: page.showInsights()
            }
            Column {
                anchors.fill: parent
                spacing: 6
                clip: true
                Repeater {
                    model: page.plan
                    Row {
                        width: parent.width
                        height: 34
                        spacing: 12
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.alpha(page.planColor(modelData.kind), 0.16)
                            Text { anchors.centerIn: parent; text: page.planSign(modelData.kind)
                                   color: page.planColor(modelData.kind); font.pixelSize: 15; font.bold: true }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 38
                            Text { width: parent.width; text: modelData.text; color: Theme.text; font.pixelSize: 14
                                   font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: modelData.detail; color: Theme.muted; font.pixelSize: 12
                                   elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            StatTile {
                Layout.fillWidth: true
                label: "Trainings"
                value: page.totals.workouts || 0
                note: Theme.num(page.streaks.workouts_per_week || 0, 1) + " pro Woche"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Harte Sätze"
                value: page.totals.work_sets || 0
                note: "ohne Aufwärmen, Drop-Teil = ½"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Bewegt gesamt"
                value: (page.totals.volume_kg || 0)
                suffix: " kg"
                note: "Gewicht × Wdh., ohne Aufwärmen"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Trainingsdauer"
                value: page.totals.avg_duration_min || 0
                formatter: function (minutes) { return Theme.duration(minutes) }
                note: (page.totals.exercises || 0) + " verschiedene Übungen"
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
                title: "Harte Sätze pro Woche"
                BarChart {
                    anchors.fill: parent
                    model: page.weekly.map(function (w) {
                        return {
                            label: Theme.day(w.week_start),
                            value: w.sets,
                            faded: !w.is_complete,
                            tip: page.weekName(w) + ": " + Theme.num(w.sets, 1).replace(",0", "") + " Sätze in " + w.workouts + " Trainings"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Bewegtes Gewicht pro Woche (kg)"
                BarChart {
                    anchors.fill: parent
                    model: page.weekly.map(function (w) {
                        return {
                            label: Theme.day(w.week_start),
                            value: w.volume_kg,
                            faded: !w.is_complete,
                            tip: page.weekName(w) + ": " + Theme.weight(w.volume_kg, 0)
                        }
                    })
                }
            }
        }
    }
}
