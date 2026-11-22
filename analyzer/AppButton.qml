import QtQuick
import QtQuick.Controls.Basic
import Workout

// AppButton : the button from the original Main.qml (inverted colours,
// 8 px corners), as a reusable component.
Button {
    id: control

    property bool secondary: false                 // true = outlined instead of filled

    font.pixelSize: 13
    leftPadding: 14
    rightPadding: 14

    contentItem: Text {
        text: control.text
        color: control.secondary ? Theme.text : Theme.surface
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        implicitWidth: 96
        implicitHeight: 36
        radius: Theme.radius
        color: control.secondary ? (control.hovered ? Theme.hover : "transparent") : Theme.text
        border.width: control.secondary ? 1 : 0
        border.color: Theme.line
        opacity: !control.enabled ? 0.4 : control.down ? 0.7 : (control.hovered && !control.secondary) ? 0.85 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
}
