import QtQuick
import Workout

// Chip : a small button that can be "on" (filled) or "off" (outlined).
Rectangle {
    id: chip

    property string text: ""
    property bool checked: false
    signal clicked()
    signal rightClicked()                          // only used where a chip has a "step back"

    implicitWidth: label.implicitWidth + 22
    implicitHeight: 30
    radius: Theme.radius
    color: checked ? Theme.text : (mouse.containsMouse ? Theme.hover : "transparent")
    border.width: 1
    border.color: checked ? Theme.text : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.fast } }

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.checked ? Theme.surface : Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (mouseEvent) {
            if (mouseEvent.button === Qt.RightButton) chip.rightClicked()
            else chip.clicked()
        }
    }
}
