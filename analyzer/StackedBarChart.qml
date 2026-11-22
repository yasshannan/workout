import QtQuick
import Workout

// StackedBarChart : one bar per entry, made of coloured parts stacked on top
// of each other, with a legend above.
//
//     StackedBarChart {
//         series: [ { name: "Drücken", color: Theme.text }, { name: "Ziehen", color: Theme.ok } ]
//         model:  [ { label: "21 Sep", values: [26, 32], faded: false, tip: "…" }, ... ]
//     }
//
//   values  one number per series, in the order of "series"
//   faded   true = drawn lighter (an unfinished week)
Item {
    id: chart

    property var model: []
    property var series: []
    property real progress: 0                      // runs 0 → 1 and makes the bars grow
    property int hovered: -1

    readonly property int count: model.length
    readonly property real leftPad: 46
    readonly property real topPad: 28              // room for the legend
    readonly property real bottomPad: 22
    readonly property real plotW: Math.max(1, width - leftPad)
    readonly property real plotH: Math.max(1, height - topPad - bottomPad)
    readonly property real slot: count > 0 ? plotW / count : plotW
    readonly property real yMax: Theme.niceMax(largest())
    readonly property int labelEvery: Math.max(1, Math.ceil(count * 52 / plotW))

    function total(values) {
        var sum = 0
        for (var i = 0; i < values.length; i++)
            sum += values[i]
        return sum
    }
    // The sum of the parts below part j.
    function below(values, j) {
        var sum = 0
        for (var i = 0; i < j; i++)
            sum += values[i]
        return sum
    }
    function largest() {
        var m = 0
        for (var i = 0; i < model.length; i++)
            m = Math.max(m, total(model[i].values))
        return m
    }

    onModelChanged: grow.restart()
    NumberAnimation {
        id: grow
        target: chart
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
    }

    // The legend.
    Row {
        x: chart.leftPad
        spacing: 16
        Repeater {
            model: chart.series
            Row {
                spacing: 6
                Rectangle {
                    width: 10
                    height: 10
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.color
                }
                Text {
                    text: modelData.name
                    color: Theme.muted
                    font.pixelSize: 12
                }
            }
        }
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

    // The bars.
    Repeater {
        model: chart.model
        Item {
            id: bar
            readonly property var entry: modelData
            readonly property real t: Theme.stagger(chart.progress, index, chart.count)
            readonly property real barWidth: Math.max(2, Math.min(46, width * 0.68))

            x: chart.leftPad + index * chart.slot
            y: chart.topPad
            width: chart.slot
            height: chart.plotH
            opacity: (entry.faded ? 0.45 : 1) * (chart.hovered === -1 || chart.hovered === index ? 1 : 0.5)
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }

            Repeater {
                model: chart.series.length
                Rectangle {
                    readonly property real value: bar.entry.values[index] || 0
                    width: bar.barWidth
                    x: (bar.width - width) / 2
                    height: chart.plotH * value / chart.yMax * bar.t
                    y: bar.height - chart.plotH * (chart.below(bar.entry.values, index) + value) / chart.yMax * bar.t
                    visible: value > 0
                    color: chart.series[index].color
                    opacity: 0.9
                }
            }
            Text {
                visible: index % chart.labelEvery === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: bar.height + 5
                text: bar.entry.label
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
        anchorY: chart.topPad + chart.plotH * (1 - (visible ? chart.total(chart.model[chart.hovered].values) : 0) / chart.yMax)
    }
}
