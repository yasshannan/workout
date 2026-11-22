import QtQuick
import QtQuick.Layouts
import Workout

// ChartsPage ("Diagramme") : everything else worth looking at, in five groups.
// Like every page it follows the date range and the exercise / muscle filter
// of the bar on top. Every chart shows details when the mouse is over it.
//
//   Gewohnheiten        weekday, time of day, length of workouts, workouts added up
//   Umfang und Tempo    kilograms and hard sets per workout, density, rests
//   Wie du trainierst   rep ranges, kinds of sets, movements per week, body regions
//   Fortschritt         progress per exercise, most trained exercises, records per month
//   Muskeln             every muscle week by week against its target
DashPage {
    id: page
    // the cards below add up to this, plus the two that grow with their content
    minimumHeight: 2450 + Math.max(290, Math.min(16, Math.max(progressRows.length, topExercises.length)) * 26 + 70)
                   + Math.max(240, matrixRows.length * 19 + 90)

    readonly property var weekdayNames: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    readonly property var weekdayLong: ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    property var weekday: []
    property var hours: []
    property var durations: []
    property var cumulative: []
    property var sessions: []
    property var repRanges: []
    property var setTypes: []
    property var restBins: []
    property var movement: []
    property var regions: []
    property var progressRows: []
    property var topExercises: []
    property var prsMonth: []
    property var matrix: []

    onRefresh: {
        weekday = backend.rows("v_chart_weekday")
        hours = backend.rows("v_chart_hours")
        durations = backend.rows("v_chart_duration_bins")
        cumulative = backend.rows("v_chart_cumulative")
        sessions = backend.rows("v_chart_sessions")
        repRanges = backend.rows("v_chart_rep_ranges")
        setTypes = backend.rows("v_chart_set_types")
        restBins = backend.rows("v_chart_rest_bins")
        movement = backend.rows("v_chart_movement_week")
        regions = backend.rows("v_chart_regions")
        progressRows = backend.rows("v_chart_progress")
        topExercises = backend.rows("v_chart_top_exercises")
        prsMonth = backend.rows("v_chart_prs_month")
        matrix = backend.rows("v_chart_muscle_matrix")
    }

    // 3 → "3", 2.5 → "2,5"
    function n1(value) {
        return Theme.num(value, 1).replace(",0", "")
    }
    function plural(count, one, many) {
        return n1(count) + " " + (count === 1 ? one : many)
    }
    function sumOf(list, key) {
        var s = 0
        for (var i = 0; i < list.length; i++)
            s += list[i][key] || 0
        return s
    }
    function share(part, whole) {
        return whole > 0 ? Theme.num(part / whole * 100, 0) + " %" : "0 %"
    }
    function signed(value) {
        return (value > 0 ? "+" : value < 0 ? "−" : "") + Theme.num(Math.abs(value), 1) + " %"
    }
    function monthLabel(iso) {
        return Theme.monthNames[parseInt(iso.split("-")[1], 10) - 1]
    }

    // The grid of muscles × weeks, built from the flat rows of v_chart_muscle_matrix.
    readonly property var matrixColumns: buildColumns()
    readonly property var matrixRows: buildRows()
    function buildColumns() {
        var weeks = []
        if (matrix.length === 0)
            return weeks
        var first = matrix[0].muscle_id
        for (var i = 0; i < matrix.length && matrix[i].muscle_id === first; i++)
            weeks.push(Theme.day(matrix[i].week_start))
        return weeks
    }
    function cellFor(r) {
        var tip = r.name + ", Woche ab " + Theme.day(r.week_start) + ": " + plural(r.sets, "Satz", "Sätze")
                  + " (Ziel " + n1(r.target_min) + "–" + n1(r.target_max) + ")" + (r.is_complete ? "" : ", läuft noch")
        if (!(r.sets > 0))
            return { empty: true, color: Theme.line, strength: 0, tip: tip }
        if (r.sets < r.target_min)
            return { empty: false, color: Theme.warn, strength: 0.15 + 0.45 * r.sets / r.target_min, tip: tip }
        if (r.sets > r.target_max)
            return { empty: false, color: Theme.high, strength: 1, tip: tip }
        var span = r.target_max - r.target_min
        return { empty: false, color: Theme.ok, strength: span > 0 ? 0.45 + 0.55 * (r.sets - r.target_min) / span : 0.8, tip: tip }
    }
    function buildRows() {
        var list = [], current = null
        for (var i = 0; i < matrix.length; i++) {
            var r = matrix[i]
            if (!current || current.id !== r.muscle_id) {
                current = { id: r.muscle_id, label: r.name, cells: [] }
                list.push(current)
            }
            current.cells.push(cellFor(r))
        }
        return list
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // ================= Gewohnheiten =================
        Text {
            text: "Gewohnheiten"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Bold
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Trainings nach Wochentag"
                BarChart {
                    anchors.fill: parent
                    model: page.weekday.map(function (r) {
                        return {
                            label: page.weekdayNames[r.weekday - 1],
                            value: r.workouts,
                            tip: page.weekdayLong[r.weekday - 1] + ": " + page.plural(r.workouts, "Training", "Trainings")
                                 + (r.workouts > 0 ? ", im Schnitt " + Theme.duration(r.avg_minutes) : "")
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Trainingsbeginn nach Uhrzeit"
                BarChart {
                    anchors.fill: parent
                    model: page.hours.map(function (r) {
                        return {
                            label: r.hour + " h",
                            value: r.workouts,
                            tip: r.hour + ":00 bis " + r.hour + ":59 Uhr: " + page.plural(r.workouts, "Training", "Trainings")
                        }
                    })
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Wie lange deine Trainings dauern (Minuten)"
                BarChart {
                    anchors.fill: parent
                    model: page.durations.map(function (r) {
                        return {
                            label: r.label,
                            value: r.workouts,
                            tip: r.label + " min: " + page.plural(r.workouts, "Training", "Trainings")
                                 + " (" + page.share(r.workouts, page.sumOf(page.durations, "workouts")) + ")"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Trainings aufsummiert"
                note: page.cumulative.length > 0 ? Theme.weight(page.cumulative[page.cumulative.length - 1].total_kg, 0) + " bewegt" : ""
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.cumulative.map(function (r) {
                        return {
                            x: Theme.dayNumber(r.day),
                            y: r.total,
                            label: Theme.day(r.day),
                            tip: Theme.dayYear(r.day) + ": " + page.plural(r.total, "Training", "Trainings")
                                 + ", zusammen " + Theme.weight(r.total_kg, 0)
                        }
                    })
                }
            }
        }

        // ================= Umfang und Tempo =================
        Text {
            text: "Umfang und Tempo"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Bold
            Layout.topMargin: 8
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Bewegtes Gewicht pro Training (kg)"
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.sessions.map(function (r) {
                        return {
                            x: Theme.dayNumber(r.day),
                            y: r.volume_kg || 0,
                            label: Theme.day(r.day),
                            tip: r.name + ", " + Theme.day(r.day) + ": " + Theme.weight(r.volume_kg || 0, 0)
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Harte Sätze pro Training"
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.sessions.map(function (r) {
                        return {
                            x: Theme.dayNumber(r.day),
                            y: r.work_sets || 0,
                            label: Theme.day(r.day),
                            tip: r.name + ", " + Theme.day(r.day) + ": " + page.plural(r.work_sets || 0, "harter Satz", "harte Sätze")
                                 + " in " + Theme.duration(r.duration_min || 0)
                        }
                    })
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Dichte: Kilogramm pro Minute"
                note: "mehr = weniger Leerlauf"
                LineChart {
                    anchors.fill: parent
                    fromZero: true
                    points: page.sessions.filter(function (r) { return r.kg_per_min > 0 }).map(function (r) {
                        return {
                            x: Theme.dayNumber(r.day),
                            y: r.kg_per_min,
                            label: Theme.day(r.day),
                            tip: r.name + ", " + Theme.day(r.day) + ": " + Theme.num(r.kg_per_min, 0) + " kg pro Minute, "
                                 + Theme.num(r.sets_per_hour, 0) + " Sätze pro Stunde"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Pausen zwischen Sätzen"
                note: "gleiche Übung"
                BarChart {
                    anchors.fill: parent
                    model: page.restBins.map(function (r) {
                        return {
                            label: r.label,
                            value: r.rests,
                            tip: r.label + ": " + page.plural(r.rests, "Pause", "Pausen")
                                 + " (" + page.share(r.rests, page.sumOf(page.restBins, "rests")) + ")"
                        }
                    })
                }
            }
        }

        // ================= Wie du trainierst =================
        Text {
            text: "Wie du trainierst"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Bold
            Layout.topMargin: 8
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Wiederholungsbereiche"
                note: "harte Sätze"
                BarChart {
                    anchors.fill: parent
                    model: page.repRanges.map(function (r) {
                        return {
                            label: r.label,
                            value: r.sets,
                            tip: r.label + " Wiederholungen: " + page.plural(r.sets, "Satz", "Sätze") + " (" + Theme.num(r.share_pct, 0) + " %)"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Satzarten"
                DonutChart {
                    anchors.fill: parent
                    unit: "Sätze"
                    model: page.setTypes.map(function (r, i) {
                        return { label: r.label, value: r.sets, color: Theme.seriesColor(i) }
                    })
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Bewegungen pro Woche"
                note: "harte Sätze"
                StackedBarChart {
                    anchors.fill: parent
                    series: [
                        { name: "Drücken", color: Theme.seriesColor(0) },
                        { name: "Ziehen", color: Theme.seriesColor(1) },
                        { name: "Beine", color: Theme.seriesColor(2) },
                        { name: "Rumpf", color: Theme.seriesColor(3) }
                    ]
                    model: page.movement.map(function (r) {
                        return {
                            label: Theme.day(r.week_start),
                            values: [r.push, r.pull, r.legs, r.core],
                            faded: !r.is_complete,
                            tip: "Woche ab " + Theme.day(r.week_start) + ": Drücken " + page.n1(r.push) + " · Ziehen " + page.n1(r.pull)
                                 + " · Beine " + page.n1(r.legs) + " · Rumpf " + page.n1(r.core)
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Körperregionen"
                note: "Muskelsätze, Nebenmuskeln anteilig"
                DonutChart {
                    anchors.fill: parent
                    unit: "Muskelsätze"
                    model: page.regions.map(function (r, i) {
                        return { label: r.label, value: r.sets, color: Theme.seriesColor(i) }
                    })
                }
            }
        }

        // ================= Fortschritt =================
        Text {
            text: "Fortschritt"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Bold
            Layout.topMargin: 8
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(290, Math.min(16, Math.max(page.progressRows.length, page.topExercises.length)) * 26 + 70)
            spacing: 16
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Fortschritt pro Übung"
                note: "erste 2 gegen letzte 2 Trainings"
                HBarChart {
                    anchors.fill: parent
                    model: page.progressRows.slice(0, 16).map(function (r) {
                        return {
                            label: r.name,
                            value: r.change_pct,
                            valueText: page.signed(r.change_pct),
                            tip: r.name + ": Kraftwert " + Theme.num(r.first_score, 1) + " → " + Theme.num(r.last_score, 1)
                                 + " kg in " + r.sessions + " Trainings"
                        }
                    })
                }
            }
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                title: "Häufigste Übungen"
                note: "harte Sätze"
                HBarChart {
                    anchors.fill: parent
                    model: page.topExercises.map(function (r) {
                        return {
                            label: r.name,
                            value: r.sets,
                            valueText: page.n1(r.sets),
                            tip: r.name + ": " + page.plural(r.sets, "Satz", "Sätze") + " in " + page.plural(r.sessions, "Training", "Trainings")
                                 + (r.volume_kg > 0 ? ", " + Theme.weight(r.volume_kg, 0) : "")
                        }
                    })
                }
            }
        }
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 290
            title: "Rekorde pro Monat"
            note: "Kraft: neues bestes geschätztes 1RM · Volumen: Gold"
            StackedBarChart {
                anchors.fill: parent
                series: [
                    { name: "Kraft-Rekorde", color: Theme.gold },
                    { name: "Volumen-Rekorde", color: Theme.seriesColor(0) }
                ]
                model: page.prsMonth.map(function (r) {
                    return {
                        label: page.monthLabel(r.month_start),
                        values: [r.strength_prs, r.volume_prs],
                        tip: page.monthLabel(r.month_start) + " " + r.month_start.split("-")[0] + ": "
                             + r.strength_prs + " Kraft-Rekorde, " + r.volume_prs + " Volumen-Rekorde"
                    }
                })
            }
        }

        // ================= Muskeln Woche für Woche =================
        Text {
            text: "Muskeln Woche für Woche"
            color: Theme.text
            font.pixelSize: 20
            font.weight: Font.Bold
            Layout.topMargin: 8
        }
        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(240, page.matrixRows.length * 19 + 90)
            title: "Harte Sätze gegen dein Ziel"
            note: "orange = darunter · grün = im Ziel · rot = sehr viel"
            MatrixChart {
                anchors.fill: parent
                columns: page.matrixColumns
                rows: page.matrixRows
            }
        }

        Item { Layout.fillHeight: true }
    }
}
