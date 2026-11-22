import QtQuick
import Workout

// StatTile : one big number with a label above and an optional note below.
Rectangle {
    id: tile

    property string label: ""
    property real value: 0
    property int decimals: 0
    property string suffix: ""
    property var formatter: null
    property string plainText: ""                  // if set, shown instead of the animated number
    property string note: ""

    implicitHeight: 96
    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.normal } }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 1

        Text {
            text: tile.label
            color: Theme.muted
            font.pixelSize: 12
        }
        AnimatedNumber {
            visible: tile.plainText === ""
            value: tile.value
            decimals: tile.decimals
            suffix: tile.suffix
            formatter: tile.formatter
        }
        Text {
            visible: tile.plainText !== ""
            text: tile.plainText
            color: Theme.text
            font.pixelSize: 24
            font.weight: Font.Bold
            width: parent.width
            elide: Text.ElideRight
        }
        Text {
            text: tile.note
            color: Theme.muted
            font.pixelSize: 12
            width: parent.width
            elide: Text.ElideRight
        }
    }
}
