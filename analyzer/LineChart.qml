import QtQuick
import QtQuick.Shapes
import Workout

// LineChart : a line that draws itself from left to right, with optional
// loose dots behind it (for example single weigh-ins behind their average).
//
//     LineChart {
//         points: [ { x: 20752, y: 84.0, label: "9 Nov", tip: "84.0 kg" }, ... ]
//         dots:   [ ... same shape ... ]
//     }
//
//   x      position on the x axis (Theme.dayNumber("2026-11-09") for dates)
//   y      the value                label  text under the axis
//   tip    text shown when the mouse is near the point
//   gold   true = a record, drawn as a bigger gold point
Item {
    id: chart

    property var points: []
    property var dots: []
    property bool fromZero: false                  // true = the y axis starts at 0
    property bool markers: true                    // small circles on the points of the line
    property real progress: 0                      // runs 0 → 1 and reveals the line
    property int hovered: -1

    readonly property real leftPad: 46
    readonly property real topPad: 10
    readonly property real bottomPad: 22
    readonly property real plotW: Math.max(1, width - leftPad - 8)
    readonly property real plotH: Math.max(1, height - topPad - bottomPad)

    // The list the mouse and the x labels work with.
    readonly property var mainList: points.length > 0 ? points : dots
    // The value range of both axes: { x0, x1, y0, y1, step, ticks }
    readonly property var range: computeRange()
    readonly property var linePath: buildPath(false)
    readonly property var areaPath: buildPath(true)
    readonly property var labelIndexes: pickLabels()

    function computeRange() {
        var list = points.concat(dots)
        if (list.length === 0)
            return { x0: 0, x1: 1, y0: 0, y1: 1, step: 0.25, ticks: 4 }
        var x0 = list[0].x, x1 = list[0].x, y0 = list[0].y, y1 = list[0].y
        for (var i = 1; i < list.length; i++) {
            x0 = Math.min(x0, list[i].x)
            x1 = Math.max(x1, list[i].x)
            y0 = Math.min(y0, list[i].y)
            y1 = Math.max(y1, list[i].y)
        }
        if (x1 === x0) {
            x0 -= 1
            x1 += 1
        }
        if (fromZero)
            y0 = 0
        if (y1 === y0)
            y1 = y0 + Math.max(1, Math.abs(y0) * 0.1)
        // Widen to round numbers, so the grid lines get pleasant labels.
        var step = Theme.niceStep((y1 - y0) / 4)
        y0 = Math.floor(y0 / step + 0.001) * step
        y1 = Math.ceil(y1 / step - 0.001) * step
        if (y1 === y0)
            y1 = y0 + step
        return { x0: x0, x1: x1, y0: y0, y1: y1, step: step, ticks: Math.round((y1 - y0) / step) }
    }

    // From a value to a position inside the plot area.
    function px(x) {
        return (x - range.x0) / (range.x1 - range.x0) * plotW
    }
    function py(y) {
        return (1 - (y - range.y0) / (range.y1 - range.y0)) * plotH
    }

    // The corner points of the line. closed = true adds the two bottom
    // corners, which gives the shape for the soft fill under the line.
    function buildPath(closed) {
        var path = []
        for (var i = 0; i < points.length; i++)
            path.push(Qt.point(px(points[i].x), py(points[i].y)))
        if (closed && path.length > 1) {
            path.push(Qt.point(px(points[points.length - 1].x), plotH))
            path.push(Qt.point(px(points[0].x), plotH))
        }
        return path
    }

    // Which points get a label under the axis (evenly spread, as many as fit).
    function pickLabels() {
        var n = mainList.length
        if (n === 0)
            return []
        var want = Math.max(2, Math.min(n, Math.floor(plotW / 90)))
        if (n === 1)
            return [0]
        var picked = []
        for (var j = 0; j < want; j++) {
            var index = Math.round(j * (n - 1) / (want - 1))
            if (picked.indexOf(index) < 0)
                picked.push(index)
        }
        return picked
    }

    // Point number i of mainList, or an empty point if there is no such point.
    function at(i) {
        return i >= 0 && i < mainList.length ? mainList[i] : { x: 0, y: 0, label: "", tip: "" }
    }

    function nearest(mouseX) {
        var best = -1
        var bestDistance = 1e12
        for (var i = 0; i < mainList.length; i++) {
            var distance = Math.abs(px(mainList[i].x) - mouseX)
            if (distance < bestDistance) {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    function replay() {
        reveal.restart()
    }
    onPointsChanged: replay()
    onDotsChanged: replay()

    NumberAnimation {
        id: reveal
        target: chart
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
        easing.type: Easing.InOutCubic
    }

    // Grid lines with their numbers.
    Repeater {
        model: chart.range.ticks + 1
        Item {
            y: chart.topPad + chart.plotH * (1 - index / chart.range.ticks)
            Rectangle {
                x: chart.leftPad
                width: chart.plotW
                height: 1
                color: Theme.line
                opacity: index === 0 ? 1 : 0.55
            }
            Text {
                width: chart.leftPad - 8
                y: -height / 2
                horizontalAlignment: Text.AlignRight
                text: Theme.axis(chart.range.y0 + index * chart.range.step)
                color: Theme.muted
                font.pixelSize: 11
            }
        }
    }

    // Labels under the axis.
    Repeater {
        model: chart.labelIndexes
        Text {
            x: chart.leftPad + chart.px(chart.at(modelData).x) - width / 2
            y: chart.topPad + chart.plotH + 5
            text: chart.at(modelData).label
            color: Theme.muted
            font.pixelSize: 11
        }
    }

    // The loose dots.
    Repeater {
        model: chart.dots
        Rectangle {
            readonly property real t: Theme.stagger(chart.progress, index, chart.dots.length)
            width: 6
            height: 6
            radius: 3
            x: chart.leftPad + chart.px(modelData.x) - 3
            y: chart.topPad + chart.py(modelData.y) - 3
            color: Theme.muted
            opacity: 0.75 * t
            scale: t
        }
    }

    // The line. It is always drawn completely, the box around it is what
    // grows from left to right and "reveals" it.
    Item {
        x: chart.leftPad
        y: chart.topPad
        width: (chart.plotW + 6) * chart.progress
        height: chart.plotH + 4
        clip: true

        Shape {
            width: chart.plotW
            height: chart.plotH
            visible: chart.points.length > 1
            preferredRendererType: Shape.CurveRenderer     // smooth edges

            ShapePath {                                     // soft fill under the line
                strokeColor: "transparent"
                fillColor: Theme.alpha(Theme.text, 0.08)
                PathPolyline { path: chart.areaPath }
            }
            ShapePath {                                     // the line itself
                strokeColor: Theme.text
                strokeWidth: 2.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: chart.linePath }
            }
        }
    }

    // Small circles on the points of the line.
    Repeater {
        model: chart.markers ? chart.points : []
        Rectangle {
            readonly property real t: Theme.stagger(chart.progress, index, chart.points.length)
            readonly property bool gold: modelData.gold === true
            // With many points only the gold ones get a circle, otherwise it gets crowded.
            visible: gold || chart.points.length <= 60
            width: gold ? 12 : 8
            height: width
            radius: width / 2
            x: chart.leftPad + chart.px(modelData.x) - width / 2
            y: chart.topPad + chart.py(modelData.y) - height / 2
            color: gold ? Theme.gold : Theme.surface
            border.width: 2
            border.color: gold ? Theme.gold : Theme.text
            scale: t
        }
    }

    Text {
        visible: chart.mainList.length === 0
        anchors.centerIn: parent
        text: "Keine Daten in diesem Zeitraum"
        color: Theme.muted
        font.pixelSize: 13
    }

    // Mouse: a thin vertical line and a tip at the nearest point.
    Rectangle {
        visible: tip.visible
        x: chart.leftPad + chart.px(chart.at(chart.hovered).x)
        y: chart.topPad
        width: 1
        height: chart.plotH
        color: Theme.muted
        opacity: 0.6
    }
    MouseArea {
        x: chart.leftPad
        y: chart.topPad
        width: chart.plotW
        height: chart.plotH
        hoverEnabled: true
        onPositionChanged: (mouse) => { chart.hovered = chart.nearest(mouse.x) }
        onExited: chart.hovered = -1
    }
    ChartTip {
        id: tip
        visible: chart.hovered >= 0 && chart.hovered < chart.mainList.length
        text: chart.at(chart.hovered).tip
        anchorX: chart.leftPad + chart.px(chart.at(chart.hovered).x)
        anchorY: chart.topPad + chart.py(chart.at(chart.hovered).y)
    }
}
