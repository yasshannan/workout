import QtQuick
import Workout

// ChartTip : the small dark label that follows the mouse over a chart.
// It places itself above the point (anchorX, anchorY) of its parent.
Rectangle {
    id: tip

    property string text: ""
    property real anchorX: 0
    property real anchorY: 0

    width: label.implicitWidth + 16
    height: label.implicitHeight + 10
    x: Math.max(0, Math.min(parent.width - width, anchorX - width / 2))
    y: Math.max(0, anchorY - height - 10)
    z: 10
    radius: 6
    color: Theme.text

    Text {
        id: label
        anchors.centerIn: parent
        text: tip.text
        color: Theme.surface
        font.pixelSize: 12
    }
}
