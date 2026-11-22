import QtQuick
import Workout

// MatrixChart : a grid of coloured cells, one row per thing (a muscle) and one
// column per period (a week). Rows and columns keep the order of the model.
//
//     MatrixChart {
//         columns: [ "21 Sep", "28 Sep", ... ]                          // labels above
//         rows: [ { label: "Brust", cells: [ { color: Theme.ok, strength: 0.8, tip: "…" }, ... ] }, ... ]
//     }
//
//   color     colour of the cell            strength  0 … 1, how full the colour is
//   empty     true = nothing in this cell (drawn as an outline only)
Item {
    id: chart

    property var columns: []
    property var rows: []
    property real progress: 0                      // runs 0 → 1, the columns fade in from the left
    property int hoverRow: -1
    property int hoverColumn: -1

    readonly property real labelWidth: Math.min(170, width * 0.24)
    readonly property real topPad: 20
    readonly property int columnCount: columns.length
    readonly property real cellW: columnCount > 0 ? Math.max(4, (width - labelWidth - 6) / columnCount) : 10
    readonly property real cellH: rows.length > 0 ? Math.max(8, Math.min(22, (height - topPad) / rows.length)) : 16
    readonly property int labelEvery: Math.max(1, Math.ceil(46 / cellW))

    onRowsChanged: grow.restart()
    NumberAnimation {
        id: grow
        target: chart
        property: "progress"
        from: 0
        to: 1
        duration: Theme.slow
    }

    // Column labels.
    Repeater {
        model: chart.columns
        Text {
            visible: index % chart.labelEvery === 0
            x: chart.labelWidth + 6 + index * chart.cellW
            text: modelData
            color: Theme.muted
            font.pixelSize: 11
        }
    }

    Repeater {
        model: chart.rows
        Item {
            id: line
            readonly property int rowIndex: index
            readonly property var cells: modelData.cells
            y: chart.topPad + index * chart.cellH
            width: chart.width
            height: chart.cellH

            Text {
                width: chart.labelWidth
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: modelData.label
                color: chart.hoverRow === line.rowIndex ? Theme.text : Theme.muted
                font.pixelSize: Math.min(12, chart.cellH - 2)
            }
            Repeater {
                model: line.cells
                Rectangle {
                    readonly property real t: Theme.stagger(chart.progress, index, chart.columnCount)
                    x: chart.labelWidth + 6 + index * chart.cellW + 1
                    y: 1
                    width: Math.max(2, chart.cellW - 2)
                    height: Math.max(2, chart.cellH - 2)
                    radius: Math.min(3, height / 3)
                    color: modelData.empty ? "transparent" : Theme.alpha(modelData.color, 0.18 + 0.82 * Math.max(0, Math.min(1, modelData.strength)))
                    border.width: modelData.empty ? 1 : 0
                    border.color: Theme.alpha(Theme.line, 0.7)
                    opacity: t * (chart.hoverRow === -1 || (chart.hoverRow === line.rowIndex && chart.hoverColumn === index) ? 1
                                  : chart.hoverRow === line.rowIndex || chart.hoverColumn === index ? 0.85 : 0.45)
                }
            }
        }
    }

    Text {
        visible: chart.rows.length === 0 || chart.columnCount === 0
        anchors.centerIn: parent
        text: "Keine Daten in diesem Zeitraum"
        color: Theme.muted
        font.pixelSize: 13
    }

    MouseArea {
        x: chart.labelWidth + 6
        y: chart.topPad
        width: Math.max(0, chart.columnCount * chart.cellW)
        height: chart.rows.length * chart.cellH
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            chart.hoverRow = Math.max(0, Math.min(chart.rows.length - 1, Math.floor(mouse.y / chart.cellH)))
            chart.hoverColumn = Math.max(0, Math.min(chart.columnCount - 1, Math.floor(mouse.x / chart.cellW)))
        }
        onExited: {
            chart.hoverRow = -1
            chart.hoverColumn = -1
        }
    }

    ChartTip {
        readonly property var cell: chart.hoverRow >= 0 && chart.hoverColumn >= 0 && chart.hoverRow < chart.rows.length
                                    ? chart.rows[chart.hoverRow].cells[chart.hoverColumn] : null
        visible: cell !== null && cell !== undefined
        text: visible ? cell.tip : ""
        anchorX: chart.labelWidth + 6 + (chart.hoverColumn + 0.5) * chart.cellW
        anchorY: chart.topPad + chart.hoverRow * chart.cellH
    }
}
