import QtQuick
import QtQuick.Controls.Basic
import Workout

// Insights : plain sentences about the data, each with its reasoning and
// source. The rules live in sql/derived.sql (the view v_insights).
DashPage {
    id: page
    minimumHeight: 500

    property var insights: []
    property real grow: 0                          // 0 → 1, the cards appear one after another

    onRefresh: {
        insights = backend.rows("v_insights")
        growAnimation.restart()
    }

    NumberAnimation {
        id: growAnimation
        target: page
        property: "grow"
        from: 0
        to: 1
        duration: Theme.slow
    }

    Text {
        id: intro
        width: parent.width
        text: "Aus den vollständigen Wochen des gewählten Zeitraums. Faustregeln aus der Trainingsforschung, keine medizinische Beratung. "
              + "„Sicherheit“ sagt, auf wie viel Daten eine Aussage beruht – mit wenig Daten wird nie gewarnt. Die Ziele änderst du in den Einstellungen."
        color: Theme.muted
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: intro.height + 12
        clip: true
        spacing: 10
        model: page.insights
        ScrollBar.vertical: ScrollBar { }

        delegate: InsightCard {
            // The first cards slide in one after another. Cards further down are simply there.
            readonly property real t: Theme.stagger(page.grow, Math.min(index, 8), 9)
            width: list.width - 12
            severity: modelData.severity
            topic: modelData.topic
            text: modelData.text
            reason: modelData.reason
            source: modelData.source
            confidence: modelData.confidence
            opacity: t
            transform: Translate { x: (1 - t) * 24 }
        }
    }
}
