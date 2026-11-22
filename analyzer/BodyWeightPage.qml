import QtQuick
import QtQuick.Layouts
import Workout

// Körper : body weight (every weigh-in as a dot, the 7-day average as the
// line, the change per week in kg and %) and the body measurements.
DashPage {
    id: page
    minimumHeight: 760

    property var entries: []                       // rows of v_bodyweight
    property var stats: ({})                       // row of v_bodyweight_stats
    property var measures: []                      // rows of v_measurements
    property var measureStats: []                  // rows of v_measurement_stats
    property string measure: "waist_cm"            // which measurement the chart shows

    readonly property real change: ((stats.last_avg || 0) - (stats.first_avg || 0))
    readonly property bool hasRate: stats.rate_kg_week !== undefined

    function signed(value, decimals, unit) {
        return (value > 0 ? "+" : value < 0 ? "−" : "") + Theme.num(Math.abs(value), decimals) + (unit === undefined ? " kg" : unit)
    }
    function measureInfo(id) {
        for (var i = 0; i < measureStats.length; i++)
            if (measureStats[i].id === id) return measureStats[i]
        return null
    }
    // What the rate per week means for a build-up or a diet.
    function rateNote(pct) {
        if (pct > 0.5) return "schnell: viel davon ist meist Fett"
        if (pct >= 0.25) return "gutes Tempo für den Aufbau"
        if (pct > -0.25) return "etwa gleich (Erhaltung)"
        if (pct >= -1.0) return "gutes Tempo für eine Diät"
        return "schnell: kostet oft Muskeln"
    }

    onRefresh: {
        entries = backend.rows("v_bodyweight")
        stats = backend.row("v_bodyweight_stats")
        measures = backend.rows("v_measurements")
        measureStats = backend.rows("v_measurement_stats")
        if (measureStats.length > 0 && measureInfo(measure) === null)
            measure = measureStats[0].id
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            StatTile {
                Layout.fillWidth: true
                label: "7-Tage-Schnitt"
                value: (page.stats.last_avg || 0)
                decimals: 1
                suffix: " kg"
                note: page.stats.last_day ? "am " + Theme.dayYear(page.stats.last_day) : "keine Einträge"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Veränderung im Zeitraum"
                value: page.change
                formatter: function (v) { return page.signed(v, 1) }
                note: page.stats.first_day ? "seit " + Theme.dayYear(page.stats.first_day) : ""
            }
            StatTile {
                Layout.fillWidth: true
                label: "Pro Woche (letzte 4 Wochen)"
                value: page.hasRate ? page.stats.rate_kg_week : 0
                formatter: function (v) { return page.signed(v, 2) }
                note: page.hasRate ? page.signed(page.stats.rate_pct_week, 2, " %") + " · " + page.rateNote(page.stats.rate_pct_week)
                                   : "braucht Einträge über 3 Wochen"
            }
            StatTile {
                Layout.fillWidth: true
                label: "Wiegungen"
                value: page.stats.entries || 0
                note: "einzelne Tage schwanken, die Linie zeigt den Trend"
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 300
            title: "Körpergewicht (kg)"
            note: "Punkte: Wiegungen · Linie: Schnitt der letzten 7 Tage"

            LineChart {
                anchors.fill: parent
                markers: false
                points: page.entries.map(function (e) {
                    return {
                        x: Theme.dayNumber(e.day),
                        y: e.avg7,
                        label: Theme.day(e.day),
                        tip: Theme.day(e.day) + ": " + Theme.weight(e.weight_kg) + " · 7-Tage-Schnitt " + Theme.weight(e.avg7)
                    }
                })
                dots: page.entries.map(function (e) {
                    return { x: Theme.dayNumber(e.day), y: e.weight_kg, label: Theme.day(e.day), tip: "" }
                })
            }
        }

        // ---------- body measurements ----------
        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 260
            title: "Körpermaße"
            note: page.measureStats.length === 0 ? "am Handy unter Start → Körpermaße eintragen" : ""

            Row {                              // which measure, with its change, placed in the title line
                anchors.right: parent.right
                y: -40
                spacing: 6
                Repeater {
                    model: page.measureStats
                    Chip {
                        text: modelData.name + " " + page.signed(modelData.last_value - modelData.first_value, 1, " " + modelData.unit)
                        checked: page.measure === modelData.id
                        onClicked: page.measure = modelData.id
                    }
                }
            }
            LineChart {
                anchors.fill: parent
                visible: page.measureStats.length > 0
                points: page.measures.filter(function (m) { return (m[page.measure] || 0) > 0 }).map(function (m) {
                    var info = page.measureInfo(page.measure)
                    var unit = info ? " " + info.unit : ""
                    return {
                        x: Theme.dayNumber(m.day),
                        y: m[page.measure],
                        label: Theme.day(m.day),
                        tip: Theme.day(m.day) + ": " + Theme.num(m[page.measure], 1) + unit
                    }
                })
            }
        }
    }
}
