import QtQuick
import Workout

// BarChart : bars drawn with plain rectangles, growing in one after another.
//
//     BarChart {
//         model: [ { label: "21 Sep", value: 75, faded: false, tip: "75 sets" }, ... ]
//     }
//
//   label  text under the bar          faded  true = drawn lighter (an unfinished week)
//   value  height of the bar           tip    text shown when the mouse is over the bar
//   gold   true = a record, drawn in gold with a small star on top
Item {
    id: chart

    property var model: []
    property real bandMin: -1                      // optional target band, for example 10 to 20 sets
    property real bandMax: -1
    property real progress: 0                      // runs 0 → 1 and makes the bars grow
    property int hovered: -1                       // index of the bar under the mouse

    readonly property int count: model.length
    readonly property real leftPad: 46             // room for the numbers of the y axis
    readonly property real topPad: 10
    readonly property real bottomPad: 22           // room for the labels of the x axis
    readonly property real plotW: Math.max(1, width - leftPad)
    readonly property real plotH: Math.max(1, height - topPad - bottomPad)
    readonly property real slot: count > 0 ? plotW / count : plotW
    readonly property real yMax: Theme.niceMax(Math.max(largest(), bandMax))
    readonly property int labelEvery: Math.max(1, Math.ceil(count * 52 / plotW))

    function largest() {
        var m = 0
        for (var i = 0; i < model.length; i++)
            m = Math.max(m, model[i].value)
        return m
    }

    // Play the grow-in animation again (called whenever new data arrives).
    function replay() {
        grow.restart()
    }
    onModelChanged: replay()

    NumberAnimation {
        id: grow
        target: chart
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
    }

    // Grid lines with their numbers.
    Repeater {
        model: 5
        Item {
            y: chart.topPad + chart.plotH * (1 - index / 4)
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
                text: Theme.axis(chart.yMax * index / 4)
                color: Theme.muted
                font.pixelSize: 11
            }
        }
    }

    // The target band.
    Rectangle {
        visible: chart.bandMax > 0
        x: chart.leftPad
        width: chart.plotW
        y: chart.topPad + chart.plotH * (1 - chart.bandMax / chart.yMax)
        height: chart.plotH * (chart.bandMax - Math.max(0, chart.bandMin)) / chart.yMax
        color: Theme.alpha(Theme.ok, 0.16)
    }

    // The bars.
    Repeater {
        model: chart.model
        Item {
            id: bar
            // This bar's own 0 → 1 value. Later bars start later.
            readonly property real t: Theme.stagger(chart.progress, index, chart.count)

            x: chart.leftPad + index * chart.slot
            y: chart.topPad
            width: chart.slot
            height: chart.plotH

            Rectangle {
                width: Math.max(2, Math.min(46, bar.width * 0.68))
                x: (bar.width - width) / 2
                height: chart.plotH * (modelData.value / chart.yMax) * bar.t
                y: bar.height - height
                radius: Math.min(4, width / 2)
                color: modelData.gold ? Theme.gold : Theme.text
                opacity: (modelData.faded ? 0.4 : 0.9) * (chart.hovered === -1 || chart.hovered === index ? 1 : 0.5)
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            }
            Text {                                 // the star on a record bar
                visible: modelData.gold === true && bar.t > 0.95
                anchors.horizontalCenter: parent.horizontalCenter
                y: bar.height - chart.plotH * (modelData.value / chart.yMax) - height - 1
                text: "★"
                color: Theme.gold
                font.pixelSize: 13
            }
            Text {
                visible: index % chart.labelEvery === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: bar.height + 5
                text: modelData.label
                color: Theme.muted
                font.pixelSize: 11
            }
        }
    }

    Text {
        visible: chart.count === 0
        anchors.centerIn: parent
        text: "Keine Daten in diesem Zeitraum"
        color: Theme.muted
        font.pixelSize: 13
    }

    MouseArea {
        x: chart.leftPad
        y: chart.topPad
        width: chart.plotW
        height: chart.plotH
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            chart.hovered = chart.count > 0 ? Math.max(0, Math.min(chart.count - 1, Math.floor(mouse.x / chart.slot))) : -1
        }
        onExited: chart.hovered = -1
    }

    ChartTip {
        visible: chart.hovered >= 0 && chart.hovered < chart.count
        text: visible ? chart.model[chart.hovered].tip : ""
        anchorX: chart.leftPad + (chart.hovered + 0.5) * chart.slot
        anchorY: chart.topPad + chart.plotH * (1 - (visible ? chart.model[chart.hovered].value : 0) / chart.yMax)
    }
}
