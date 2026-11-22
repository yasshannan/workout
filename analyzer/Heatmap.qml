import QtQuick
import Workout

// Heatmap : a calendar with one small square per day (one column per week,
// Monday at the top). The darker the square, the more hard sets that day.
//
//     Heatmap {
//         firstDay: "2026-09-21"
//         lastDay: "2026-11-15"
//         days: [ { day: "2026-09-21", sets: 17, workouts: 1, minutes: 62 }, ... ]
//     }
Item {
    id: map

    property string firstDay: ""
    property string lastDay: ""
    property var days: []
    property real progress: 0                      // runs 0 → 1, the columns fade in one by one
    property int hovered: -1

    readonly property var cells: buildCells()      // [{ day, column, row, sets, workouts, minutes, month }]
    readonly property int columns: cells.length > 0 ? cells[cells.length - 1].column + 1 : 0
    readonly property real most: largest()
    readonly property real leftPad: 34
    readonly property real topPad: 18
    readonly property real cell: Math.max(6, Math.min(26, Math.min((width - leftPad) / Math.max(1, columns),
                                                                    (height - topPad) / 7)))

    function largest() {
        var m = 0
        for (var i = 0; i < days.length; i++)
            m = Math.max(m, days[i].sets)
        return m
    }

    // "2026-09-21" -> a JavaScript Date at noon (noon avoids trouble with summer time).
    function toDate(iso) {
        var p = iso.split("-")
        return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10), 12, 0, 0)
    }
    function toIso(date) {
        var m = date.getMonth() + 1
        var d = date.getDate()
        return date.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (d < 10 ? "0" : "") + d
    }

    // One entry per day from the Monday of the first week to the last day.
    function buildCells() {
        if (firstDay === "" || lastDay === "" || firstDay > lastDay)
            return []
        var byDay = {}
        for (var i = 0; i < days.length; i++)
            byDay[days[i].day] = days[i]

        var date = toDate(firstDay)
        date.setDate(date.getDate() - (date.getDay() + 6) % 7)      // back to Monday
        var end = toDate(lastDay)
        // Never more than a year, the squares would get too small.
        var earliest = new Date(end.getTime())
        earliest.setDate(earliest.getDate() - 53 * 7)
        while (date < earliest)
            date.setDate(date.getDate() + 7)

        var result = []
        var index = 0
        var lastMonth = -1
        while (date <= end) {
            var iso = toIso(date)
            var info = byDay[iso]
            var row = index % 7
            var monthLabel = ""
            if (row === 0 && date.getMonth() !== lastMonth) {
                monthLabel = Theme.monthNames[date.getMonth()]
                lastMonth = date.getMonth()
            }
            result.push({
                day: iso,
                column: Math.floor(index / 7),
                row: row,
                sets: info ? info.sets : 0,
                workouts: info ? info.workouts : 0,
                minutes: info ? info.minutes : 0,
                month: monthLabel
            })
            date.setDate(date.getDate() + 1)
            index++
        }
        return result
    }

    function replay() {
        fade.restart()
    }
    onCellsChanged: replay()

    NumberAnimation {
        id: fade
        target: map
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
    }

    // Mon / Wed / Fri at the left.
    Repeater {
        model: ["Mo", "", "Mi", "", "Fr", "", ""]
        Text {
            x: 0
            y: map.topPad + index * map.cell + (map.cell - height) / 2
            text: modelData
            color: Theme.muted
            font.pixelSize: 10
        }
    }

    Repeater {
        model: map.cells
        Item {
            x: map.leftPad + modelData.column * map.cell
            y: map.topPad + modelData.row * map.cell
            width: map.cell
            height: map.cell

            Text {                                 // month name above the first week of a month
                visible: modelData.month !== ""
                y: -map.topPad + 2
                text: modelData.month
                color: Theme.muted
                font.pixelSize: 10
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: Math.max(1, map.cell * 0.09)
                radius: 3
                color: modelData.sets > 0
                       ? Theme.alpha(Theme.text, 0.25 + 0.7 * modelData.sets / Math.max(1, map.most))
                       : Theme.alpha(Theme.text, 0.07)
                border.width: map.hovered === index ? 2 : 0
                border.color: Theme.text
                opacity: Theme.stagger(map.progress, modelData.column, map.columns)
                scale: 0.6 + 0.4 * opacity
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: map.hovered = index
                onExited: if (map.hovered === index) map.hovered = -1
            }
        }
    }

    Text {
        visible: map.cells.length === 0
        anchors.centerIn: parent
        text: "Keine Daten in diesem Zeitraum"
        color: Theme.muted
        font.pixelSize: 13
    }

    ChartTip {
        readonly property var info: visible ? map.cells[map.hovered] : null
        visible: map.hovered >= 0 && map.hovered < map.cells.length
        text: info ? Theme.dayYear(info.day) + (info.workouts > 0
                        ? ": " + Theme.num(info.sets, 1).replace(",0", "") + " Sätze, " + Theme.duration(info.minutes)
                        : ": Ruhetag") : ""
        anchorX: info ? map.leftPad + (info.column + 0.5) * map.cell : 0
        anchorY: info ? map.topPad + info.row * map.cell : 0
    }
}
