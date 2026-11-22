import QtQuick
import Workout

// SplitBar : two numbers shown as the two parts of one bar, for example
// push against pull. The dividing point slides to its place.
Item {
    id: split

    property string leftLabel: ""
    property string rightLabel: ""
    property real leftValue: 0
    property real rightValue: 0
    property string unitText: "Sätze/Woche"

    readonly property real total: leftValue + rightValue
    readonly property real share: total > 0 ? leftValue / total : 0.5
    property real shown: 0.5                       // the share on screen, it slides to "share"

    implicitHeight: 54
    onShareChanged: shown = share
    Component.onCompleted: shown = share
    Behavior on shown { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }

    Text {
        text: split.leftLabel + "  " + Theme.num(split.leftValue, 1)
        color: Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right
        text: Theme.num(split.rightValue, 1) + "  " + split.rightLabel
        color: Theme.text
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: split.total > 0 ? Math.round(split.share * 100) + " : " + (100 - Math.round(split.share * 100)) : split.unitText
        color: Theme.muted
        font.pixelSize: 12
    }

    Rectangle {                                    // right part (the whole bar, lighter)
        id: bar
        y: 24
        width: parent.width
        height: 14
        radius: 7
        color: Theme.alpha(Theme.text, 0.3)
    }
    Rectangle {                                    // left part
        y: 24
        width: Math.max(14, bar.width * split.shown)
        height: 14
        radius: 7
        color: Theme.text
        visible: split.total > 0
    }
    Rectangle {                                    // a small mark at the middle
        x: bar.width / 2
        y: 20
        width: 1
        height: 22
        color: Theme.muted
    }
}
