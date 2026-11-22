import QtQuick
import Workout

// AnimatedNumber : a number that counts up (or down) to its new value.
Text {
    id: root

    property real value: 0
    property int decimals: 0
    property string suffix: ""
    property var formatter: null                   // optional: function(number) returning the text
    property real shown: 0                         // the number on screen right now, it runs after "value"

    text: formatter ? formatter(shown) : Theme.num(shown, decimals) + suffix
    color: Theme.text
    font.pixelSize: 28
    font.weight: Font.Bold

    Behavior on shown { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    onValueChanged: shown = value
    Component.onCompleted: shown = value
}
