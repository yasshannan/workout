import QtQuick
import Workout

// RangeBar : one muscle as a row. A bar shows the weekly sets, the shaded
// part of the track is the target range, and a label says where you stand.
// The status is always written out, never shown by colour alone.
Item {
    id: row

    property string name: ""
    property real value: 0                         // hard sets per week
    property real sessions: 0                      // sessions per week
    property real targetMin: 10
    property real targetMax: 20
    property real scaleMax: 30                     // the value at the right end of the track
    property string status: "ok"                   // "none", "idle", "under", "ok" or "high"
    property real t: 1                             // 0 → 1 grow-in, driven by the page
    property bool selected: false
    signal clicked()

    readonly property color tone: Theme.statusColor(status)
    readonly property string statusText: status === "ok" ? "Im Ziel" : status === "high" ? "Sehr hoch"
                                       : status === "none" ? "Keine Sätze" : status === "idle" ? "Freiwillig" : "Zu wenig"

    implicitHeight: 34

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: row.selected ? Theme.hover : mouse.containsMouse ? Theme.alpha(Theme.text, 0.045) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    Text {
        x: 8
        width: 92
        anchors.verticalCenter: parent.verticalCenter
        text: row.name
        color: Theme.text
        font.pixelSize: 13
        font.weight: row.selected ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
    }

    Item {
        id: track
        x: 108
        width: Math.max(20, row.width - 108 - 190)
        height: 12
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {                                // the empty track
            anchors.fill: parent
            radius: 6
            color: Theme.line
            opacity: 0.55
        }
        Rectangle {                                // the target range
            x: track.width * Math.min(1, row.targetMin / row.scaleMax)
            width: track.width * Math.max(0, Math.min(row.targetMax, row.scaleMax) - row.targetMin) / row.scaleMax
            height: parent.height
            color: Theme.alpha(Theme.ok, 0.32)
        }
        Rectangle {                                // the value
            width: row.value > 0 ? Math.max(4, track.width * Math.min(1, row.value / row.scaleMax) * row.t) : 0
            height: parent.height
            radius: 6
            color: Theme.text
        }
    }

    Text {
        x: row.width - 182
        width: 40
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Theme.num(row.value * row.t, 1)
        color: Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    Text {
        x: row.width - 134
        width: 44
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Theme.num(row.sessions, 1) + "×"
        color: Theme.muted
        font.pixelSize: 12
    }
    Rectangle {                                    // the status label
        x: row.width - 80
        width: 74
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.alpha(row.tone, 0.16)
        opacity: row.t
        Text {
            anchors.centerIn: parent
            text: row.statusText
            color: row.tone
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
