import QtQuick
import Workout

// InsightCard : one sentence from the insights, with its reasoning and source.
//
//   severity  "warn" (worth acting on), "good" or "info"
//   compact   true = only the sentence (used on the Overview page)
Rectangle {
    id: card

    property string severity: "info"
    property string topic: ""
    property string text: ""
    property string reason: ""
    property string source: ""
    property string confidence: ""                 // "hoch", "mittel" or "niedrig": how much data it rests on
    property bool compact: false

    readonly property color tone: Theme.statusColor(severity)
    readonly property string label: severity === "warn" ? "Handeln" : severity === "good" ? "Läuft gut" : "Gut zu wissen"

    implicitHeight: column.implicitHeight + 24
    color: Theme.surface
    radius: Theme.radius
    border.width: 1
    border.color: Theme.line
    Behavior on color { ColorAnimation { duration: Theme.normal } }

    Rectangle {                                    // coloured strip at the left edge
        x: 8
        y: 10
        width: 4
        height: parent.height - 20
        radius: 2
        color: card.tone
    }

    Column {
        id: column
        x: 22
        y: 12
        width: parent.width - 36
        spacing: 4

        Row {
            spacing: 8
            Text {
                text: card.label
                color: card.tone
                font.pixelSize: 11
                font.weight: Font.Bold
            }
            Text {
                text: card.topic
                color: Theme.muted
                font.pixelSize: 11
            }
            Text {
                visible: card.confidence !== ""
                text: "· Sicherheit: " + card.confidence
                color: card.confidence === "niedrig" ? Theme.warn : Theme.muted
                font.pixelSize: 11
            }
        }
        Text {
            width: parent.width
            text: card.text
            color: Theme.text
            font.pixelSize: card.compact ? 13 : 15
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Text {
            visible: !card.compact && card.reason !== ""
            width: parent.width
            text: card.reason
            color: Theme.text
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
        Text {
            visible: !card.compact && card.source !== ""
            width: parent.width
            text: "Quelle: " + card.source
            color: Theme.muted
            font.pixelSize: 12
            font.italic: true
            wrapMode: Text.WordWrap
        }
    }
}
