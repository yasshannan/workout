import QtQuick
import QtQuick.Shapes
import Workout

// DonutChart : shares of a whole as a ring, with a legend at the right.
//
//     DonutChart {
//         model: [ { label: "Oberkörper", value: 866, color: Theme.text, tip: "…" }, ... ]
//         unit: "Sätze"
//     }
//
// The ring grows around clockwise, starting at the top. The middle shows the
// total, or the share of the part under the mouse.
Item {
    id: chart

    property var model: []
    property string unit: ""
    property real progress: 0                      // runs 0 → 1 and draws the ring
    property int hovered: -1

    readonly property int count: model.length
    readonly property real sum: total()
    readonly property real size: Math.max(40, Math.min(height, width * 0.5))
    readonly property real ring: Math.max(10, size * 0.16)       // thickness of the ring
    readonly property real cx: size / 2
    readonly property real cy: height / 2
    readonly property real radius: size / 2 - ring / 2 - 2

    function total() {
        var s = 0
        for (var i = 0; i < model.length; i++)
            s += Math.max(0, model[i].value)
        return s
    }
    // Where part i starts, in degrees clockwise from the top.
    function startAngle(i) {
        var s = 0
        for (var j = 0; j < i; j++)
            s += Math.max(0, model[j].value)
        return sum > 0 ? s / sum * 360 : 0
    }
    function sweep(i) {
        return sum > 0 ? Math.max(0, model[i].value) / sum * 360 : 0
    }
    function colorOf(i) {
        return model[i].color !== undefined ? model[i].color : Theme.seriesColor(i)
    }
    function percent(i) {
        return sum > 0 ? Math.max(0, model[i].value) / sum * 100 : 0
    }
    // The part under the mouse, from its angle around the centre.
    function partAt(x, y) {
        var dx = x - cx, dy = y - cy
        var distance = Math.sqrt(dx * dx + dy * dy)
        if (distance < radius - ring / 2 - 4 || distance > radius + ring / 2 + 4)
            return -1
        var angle = Math.atan2(dy, dx) * 180 / Math.PI + 90         // 0 = top, clockwise
        if (angle < 0)
            angle += 360
        for (var i = 0; i < count; i++)
            if (sweep(i) > 0 && angle >= startAngle(i) && angle < startAngle(i) + sweep(i))
                return i
        return -1
    }

    onModelChanged: grow.restart()
    NumberAnimation {
        id: grow
        target: chart
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
        easing.type: Easing.OutCubic
    }

    // The grey track behind the ring.
    Shape {
        visible: chart.sum > 0
        width: chart.size
        height: chart.height
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.alpha(Theme.text, 0.08)
            strokeWidth: chart.ring
            fillColor: "transparent"
            PathAngleArc {
                centerX: chart.cx
                centerY: chart.cy
                radiusX: chart.radius
                radiusY: chart.radius
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // One arc per part.
    Repeater {
        model: chart.count
        Shape {
            width: chart.size
            height: chart.height
            preferredRendererType: Shape.CurveRenderer
            visible: chart.sweep(index) > 0
            opacity: chart.hovered === -1 || chart.hovered === index ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            ShapePath {
                strokeColor: chart.colorOf(index)
                strokeWidth: chart.ring
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: chart.cx
                    centerY: chart.cy
                    radiusX: chart.radius
                    radiusY: chart.radius
                    // QML angles: 0 = 3 o'clock, clockwise. -90 moves the start to the top.
                    startAngle: -90 + chart.startAngle(index) * chart.progress
                    sweepAngle: Math.max(0, chart.sweep(index) * chart.progress - 0.8)   // a hair of space between parts
                }
            }
        }
    }

    // The middle: total, or the part under the mouse.
    Column {
        visible: chart.sum > 0
        x: chart.cx - width / 2
        y: chart.cy - height / 2
        width: chart.radius * 1.4
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: chart.hovered >= 0 ? Theme.num(chart.percent(chart.hovered), 0) + " %" : Theme.num(chart.sum, 0)
            color: Theme.text
            font.pixelSize: Math.max(14, chart.size * 0.13)
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: chart.hovered >= 0 ? chart.model[chart.hovered].label : chart.unit
            color: Theme.muted
            font.pixelSize: 12
        }
    }

    MouseArea {
        width: chart.size
        height: chart.height
        hoverEnabled: true
        onPositionChanged: (mouse) => { chart.hovered = chart.partAt(mouse.x, mouse.y) }
        onExited: chart.hovered = -1
    }

    // The legend: colour, name, number and share. Hovering a line lights up its part.
    Column {
        visible: chart.sum > 0
        x: chart.size + 20
        width: Math.max(0, chart.width - x)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: chart.model
            Item {
                width: parent.width
                height: 22
                opacity: chart.hovered === -1 || chart.hovered === index ? 1 : 0.5
                Rectangle {
                    width: 12
                    height: 12
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: chart.colorOf(index)
                }
                Text {
                    x: 20
                    width: parent.width - 20 - share.width - 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: modelData.label
                    color: Theme.text
                    font.pixelSize: 13
                }
                Text {
                    id: share
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.num(modelData.value, 0) + " · " + Theme.num(chart.percent(index), 0) + " %"
                    color: Theme.muted
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: chart.hovered = index
                    onExited: chart.hovered = -1
                }
            }
        }
    }

    Text {
        visible: chart.sum <= 0
        anchors.centerIn: parent
        text: "Keine Daten in diesem Zeitraum"
        color: Theme.muted
        font.pixelSize: 13
    }
}
