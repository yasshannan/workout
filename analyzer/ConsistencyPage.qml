import QtQuick
import QtQuick.Layouts
import Workout

// Consistency : workouts per week, streaks, and a calendar of training days.
DashPage {
    id: page
    minimumHeight: 620

    property var weekly: []                        // rows of v_weekly
    property var streaks: ({})                     // row of v_streaks
    property var days: []                          // rows of v_days
    property var totals: ({})
    property var info: ({})                        // row of v_state

    function weeksText(n) {
        return n + (n === 1 ? " Woche" : " Wochen")
    }

    onRefresh: {
        weekly = backend.rows("v_weekly")
        streaks = backend.row("v_streaks")
        totals = backend.row("v_totals")
        info = backend.row("v_state")
        days = backend.rows("v_days")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            StatTile {
                Layout.fillWidth: true
                label: "Trainings pro Woche"
                value: page.streaks.workouts_per_week || 0
                decimals: 1
                note: "Schnitt der vollständigen Wochen"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Aktuelle Serie"
                value: page.streaks.current_streak || 0
                formatter: function (v) { return page.weeksText(Math.round(v)) }
                note: "Wochen in Folge mit Training"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Längste Serie"
                value: page.streaks.longest_streak || 0
                formatter: function (v) { return page.weeksText(Math.round(v)) }
                note: "in diesem Zeitraum"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Aktive Wochen"
                plainText: (page.streaks.active_weeks || 0) + " von " + (page.streaks.counted_weeks || 0)
                note: "Wochen mit mindestens einem Training"
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
                title: "Trainings pro Woche"
                BarChart {
                    anchors.fill: parent
                    model: page.weekly.map(function (w) {
                        return {
                            label: Theme.day(w.week_start),
                            value: w.workouts,
                            faded: !w.is_complete,
                            tip: "Woche ab " + Theme.day(w.week_start) + ": " + w.workouts
                                 + (w.workouts === 1 ? " Training, " : " Trainings, ") + Theme.duration(w.minutes)
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Trainingskalender"
                note: "dunkler = mehr harte Sätze"
                Heatmap {
                    anchors.fill: parent
                    firstDay: page.totals.first_day || ""
                    lastDay: page.info.end_day || ""
                    days: page.days
                }
            }
        }
    }
}
