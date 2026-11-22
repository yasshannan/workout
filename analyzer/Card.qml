import QtQuick
import Workout

// Card : a panel with a title. Whatever you put inside goes below the title.
//
//     Card {
//         title: "Hard sets per week"
//         BarChart { anchors.fill: parent }
//     }
Rectangle {
    id: card

    property string title: ""
    property string note: ""                       // small grey text at the right of the title
    default property alias content: body.data      // children of a Card land in "body"

    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.normal } }

    Text {
        id: heading
        x: 16
        y: 13
        text: card.title
        color: Theme.text
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 15
        text: card.note
        color: Theme.muted
        font.pixelSize: 12
    }
    Item {
        id: body
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: card.title !== "" ? 46 : 16
    }
}
