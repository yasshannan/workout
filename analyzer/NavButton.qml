import QtQuick
import Workout

// NavButton : one entry of the sidebar.
Item {
    id: nav

    property string text: ""
    property bool current: false
    signal clicked()

    width: parent ? parent.width : 180
    height: 40

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        radius: Theme.radius
        color: mouse.containsMouse && !nav.current ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Text {
        x: 26
        anchors.verticalCenter: parent.verticalCenter
        text: nav.text
        color: nav.current ? Theme.surface : Theme.text
        font.pixelSize: 14
        font.weight: nav.current ? Font.DemiBold : Font.Normal
        Behavior on color { ColorAnimation { duration: Theme.normal } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: nav.clicked()
    }
}
