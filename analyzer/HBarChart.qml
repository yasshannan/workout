import QtQuick
import Workout

// HBarChart : horizontal bars, one row per entry, the name on the left and the
// number in a column on the right. Rows keep the order of the model.
//
//     HBarChart {
//         model: [ { label: "Bench Press", value: 12.5, valueText: "+12,5 %", tip: "…" }, ... ]
//     }
//
// When some values are negative (changes in %), the bars grow to both sides
// of a zero line in the middle: green to the right, red to the left.
//   color  optional colour of one bar
Item {
    id: chart

    property var model: []
    property real progress: 0                      // runs 0 → 1 and makes the bars grow
    property int hovered: -1

    readonly property int count: model.length
    readonly property real labelWidth: Math.min(200, width * 0.36)
    readonly property real valueWidth: 70          // the column with the numbers
    readonly property real barX: labelWidth + 10
    readonly property real barW: Math.max(1, width - barX - valueWidth - 8)
    readonly property bool signedValues: hasNegative()
    readonly property real zeroX: signedValues ? barX + barW / 2 : barX
    readonly property real maxAbs: largest()
    readonly property real step: count > 0 ? Math.max(14, Math.min(30, height / count)) : 30

    function largest() {
        var m = 0
        for (var i = 0; i < model.length; i++)
            m = Math.max(m, Math.abs(model[i].value))
        return m > 0 ? m : 1
    }
    function hasNegative() {
        for (var i = 0; i < model.length; i++)
            if (model[i].value < 0)
                return true
        return false
    }
    // The length of a bar in pixels at the end of the grow-in.
    function barLength(value) {
        return (signedValues ? barW / 2 : barW) * Math.abs(value) / maxAbs
    }
    function barColor(entry) {
        if (entry.color !== undefined)
            return entry.color
        if (!signedValues)
            return Theme.text
        return entry.value < 0 ? Theme.high : Theme.ok
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

    Rectangle {                                    // the zero line
        visible: chart.signedValues && chart.count > 0
        x: chart.zeroX
        width: 1
        height: chart.count * chart.step
        color: Theme.line
    }

    Repeater {
        model: chart.model
        Item {
            id: row
            readonly property real t: Theme.stagger(chart.progress, index, chart.count)
            readonly property real len: chart.barLength(modelData.value) * t

            y: index * chart.step
            width: chart.width
            height: chart.step
            opacity: chart.hovered === -1 || chart.hovered === index ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }

            Text {
                width: chart.labelWidth
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: modelData.label
                color: Theme.text
                font.pixelSize: 12
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(6, Math.min(18, chart.step * 0.62))
                width: modelData.value === 0 ? 0 : Math.max(2, row.len)
                x: modelData.value < 0 ? chart.zeroX - width : chart.zeroX
                radius: Math.min(4, height / 2)
                color: chart.barColor(modelData)
                opacity: 0.88
            }
            Text {
                x: chart.width - chart.valueWidth
                width: chart.valueWidth
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: modelData.valueText !== undefined ? modelData.valueText : Theme.num(modelData.value, 1)
                color: Theme.muted
                font.pixelSize: 12
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
        width: chart.width
        height: chart.count * chart.step
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            chart.hovered = chart.count > 0 ? Math.max(0, Math.min(chart.count - 1, Math.floor(mouse.y / chart.step))) : -1
        }
        onExited: chart.hovered = -1
    }

    ChartTip {
        visible: chart.hovered >= 0 && chart.hovered < chart.count && text !== ""
        text: chart.hovered >= 0 && chart.hovered < chart.count ? (chart.model[chart.hovered].tip || "") : ""
        anchorX: chart.hovered >= 0 && chart.hovered < chart.count
                 ? chart.zeroX + (chart.model[chart.hovered].value < 0 ? -1 : 1) * chart.barLength(chart.model[chart.hovered].value)
                 : 0
        anchorY: (chart.hovered + 0.2) * chart.step
    }
}
