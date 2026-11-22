import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Workout

// Settings : display options, the training level, weekly targets per muscle,
// and which muscles each exercise trains (and how much).
DashPage {
    id: page
    minimumHeight: 640

    property var info: ({})                        // row of v_state
    property var muscles: []                       // v_muscle_list
    property var exercises: []                     // v_exercises_all
    property string search: ""
    property string editing: ""                    // id of the exercise whose muscles are being edited
    property var primary: []
    property var secondary: []
    property var shares: ({})                      // secondary muscle id → 0.1 … 0.9

    readonly property var shown: exercises.filter(function (e) {
        return search === "" || e.name.toLowerCase().indexOf(search.toLowerCase()) >= 0
    })

    function edit(e) {
        editing = e.id
        primary = e.primary_ids === "" ? [] : e.primary_ids.split(",")
        secondary = e.secondary_ids === "" ? [] : e.secondary_ids.split(",")
        var map = {}
        if (e.secondary_shares !== "")
            e.secondary_shares.split(",").forEach(function (pair) { var p = pair.split(":"); map[p[0]] = Number(p[1]) })
        shares = map
    }
    // Left click cycles: not trained → main (1) → 0,9 → 0,8 … 0,1 → not trained.
    // Right click goes one step back (0,4 → 0,5), so a value is quick to fix.
    function cycle(id, back) {
        var p = primary.slice(), s = secondary.slice(), m = Object.assign({}, shares)
        var share = m[id] === undefined ? 0.5 : m[id]
        if (back) {
            if (s.indexOf(id) >= 0 && share < 0.85) m[id] = Math.round(share * 10 + 1) / 10
            else if (s.indexOf(id) >= 0) { s.splice(s.indexOf(id), 1); delete m[id]; p.push(id) }
            else if (p.indexOf(id) < 0) { s.push(id); m[id] = 0.1 }
        } else if (p.indexOf(id) >= 0) { p.splice(p.indexOf(id), 1); s.push(id); m[id] = 0.9 }
        else if (s.indexOf(id) >= 0) {
            if (share > 0.15) m[id] = Math.round(share * 10 - 1) / 10
            else { s.splice(s.indexOf(id), 1); delete m[id] }
        }
        else p.push(id)
        primary = p
        secondary = s
        shares = m
    }
    function shareText(share) {
        return Theme.num(share, 1)
    }

    onRefresh: {
        info = backend.row("v_state")
        muscles = backend.rows("v_muscle_list")
        exercises = backend.rows("v_exercises_all")
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        ColumnLayout {
            Layout.preferredWidth: 430
            Layout.fillHeight: true
            spacing: 16

            Card {
                Layout.fillWidth: true
                Layout.preferredHeight: 250
                title: "Anzeige und Rechnen"
                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    rowSpacing: 10
                    columnSpacing: 16
                    Text { text: "Farben"; color: Theme.text; font.pixelSize: 13 }
                    Row { spacing: 6
                        Repeater { model: [["auto", "Wie Windows"], ["light", "Hell"], ["dark", "Dunkel"]]
                            Chip { text: modelData[1]; checked: Theme.mode === modelData[0]
                                onClicked: { backend.setOption("theme", modelData[0]); Theme.mode = modelData[0] } } } }
                    Text { text: "1RM-Formel"; color: Theme.text; font.pixelSize: 13 }
                    Row { spacing: 6
                        Chip { text: "Epley"; checked: page.info.formula === "epley"; onClicked: backend.setOption("formula", "epley") }
                        Chip { text: "Brzycki"; checked: page.info.formula === "brzycki"; onClicked: backend.setOption("formula", "brzycki") } }
                    Text { text: "Animationen"; color: Theme.text; font.pixelSize: 13 }
                    Row { spacing: 6
                        Chip { text: "An"; checked: Theme.animations; onClicked: { backend.setOption("animations", 1); Theme.animations = true } }
                        Chip { text: "Aus"; checked: !Theme.animations; onClicked: { backend.setOption("animations", 0); Theme.animations = false } } }
                    // The weekly targets for every muscle at once: fewer sets do the job for a
                    // beginner, an advanced lifter needs more. Changing one target makes it "Eigene".
                    Text { text: "Trainingsstand"; color: Theme.text; font.pixelSize: 13 }
                    Row { spacing: 6
                        Repeater { model: [["beginner", "Anfänger"], ["intermediate", "Fortgeschritten"], ["advanced", "Erfahren"]]
                            Chip { text: modelData[1]; checked: page.info.level === modelData[0]; onClicked: backend.setLevel(modelData[0]) } }
                        Chip { visible: page.info.level === "custom"; text: "Eigene"; checked: true } }
                }
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                title: "Wochenziel pro Muskel"
                note: "harte Sätze: Minimum – Maximum"
                ListView {
                    id: targets
                    anchors.fill: parent
                    clip: true
                    model: page.muscles
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Item {
                        width: targets.width - 10
                        height: 36
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: Theme.text; font.pixelSize: 13 }
                        DateField {
                            id: minField
                            x: parent.width - 150; width: 64; anchors.verticalCenter: parent.verticalCenter
                            text: Theme.num(modelData.target_min); horizontalAlignment: TextInput.AlignHCenter
                            onEditingFinished: backend.setMuscleTarget(modelData.id, Number(minField.text), Number(maxField.text))
                        }
                        DateField {
                            id: maxField
                            x: parent.width - 70; width: 64; anchors.verticalCenter: parent.verticalCenter
                            text: Theme.num(modelData.target_max); horizontalAlignment: TextInput.AlignHCenter
                            onEditingFinished: backend.setMuscleTarget(modelData.id, Number(minField.text), Number(maxField.text))
                        }
                    }
                }
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: "Welche Muskeln trainiert eine Übung?"
            note: "Muskel anklicken: Hauptmuskel (1) → 0,9 … 0,1 → keiner · Rechtsklick: zurück"

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                DateField {
                    Layout.preferredWidth: 280
                    placeholderText: "Übung suchen"
                    onTextChanged: page.search = text
                }
                ListView {
                    id: exList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: page.shown
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Item {
                        readonly property bool open: modelData.id === page.editing
                        width: exList.width - 10
                        height: open ? 46 + chips.implicitHeight + 50 : 40
                        Behavior on height { NumberAnimation { duration: Theme.fast } }
                        clip: true

                        Rectangle { anchors.fill: parent; radius: 6; color: open ? Theme.hover : "transparent" }
                        Text {
                            x: 8; y: 11
                            text: modelData.name + (modelData.is_custom ? "  ★ eigene" : "")
                            color: Theme.text; font.pixelSize: 13; font.weight: open ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 8; y: 12
                            text: modelData.sets + " gespeicherte Sätze"
                            color: Theme.muted; font.pixelSize: 12
                        }
                        MouseArea { width: parent.width; height: 40; cursorShape: Qt.PointingHandCursor; onClicked: page.edit(modelData) }

                        Flow {
                            id: chips
                            visible: open
                            x: 8; y: 44
                            width: parent.width - 16
                            spacing: 6
                            Repeater {
                                model: page.muscles
                                Chip {
                                    readonly property bool isPrimary: page.primary.indexOf(modelData.id) >= 0
                                    readonly property bool isSecondary: page.secondary.indexOf(modelData.id) >= 0
                                    text: modelData.name + (isPrimary ? " · 1" : isSecondary
                                          ? " · " + page.shareText(page.shares[modelData.id] === undefined ? 0.5 : page.shares[modelData.id]) : "")
                                    checked: isPrimary
                                    border.color: isSecondary ? Theme.text : Theme.line
                                    border.width: isSecondary ? 2 : 1
                                    onClicked: page.cycle(modelData.id, false)
                                    onRightClicked: page.cycle(modelData.id, true)
                                }
                            }
                        }
                        Row {
                            visible: open
                            x: 8; y: 44 + chips.implicitHeight + 10
                            spacing: 8
                            AppButton { text: "Speichern"; implicitHeight: 32
                                onClicked: { backend.setExerciseMuscles(page.editing, page.primary, page.secondary, page.shares); page.editing = "" } }
                            AppButton { secondary: true; text: "Abbrechen"; implicitHeight: 32; onClicked: page.editing = "" }
                        }
                    }
                }
            }
        }
    }
}
