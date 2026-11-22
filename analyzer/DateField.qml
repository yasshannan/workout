import QtQuick
import QtQuick.Controls.Basic
import Workout

// DateField : a small text field in the app's colours (used for dates and numbers).
TextField {
    id: field

    implicitWidth: 138
    implicitHeight: 30
    leftPadding: 10
    rightPadding: 10
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: 13
    color: Theme.text
    placeholderTextColor: Theme.muted
    selectByMouse: true

    background: Rectangle {
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: field.activeFocus ? Theme.text : Theme.line
    }
}
