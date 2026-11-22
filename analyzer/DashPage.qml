import QtQuick
import QtQuick.Controls.Basic
import Workout

// DashPage : what all pages have in common.
//
//   * "refresh" is sent whenever the page should load its data again: when
//     it becomes the visible page, and when data or filters change while it
//     is visible. A page reacts with   onRefresh: { ... backend.rows(...) ... }
//   * Every time the page is shown, its content fades and slides in.
//
// Children of a DashPage are placed inside "holder", the part that moves.
//
// SMALL WINDOWS: a page never gets squeezed below minimumHeight. If the window
// is lower than that, the page scrolls (mouse wheel or the bar at the right)
// instead of charts and cards being pushed on top of each other.
Item {
    id: page

    property bool active: false                    // true while this is the visible page
    property real minimumHeight: 700               // below this height the page scrolls
    signal refresh()
    default property alias content: holder.data

    onActiveChanged: {
        if (active) {
            refresh()
            enter.restart()
        }
    }
    Component.onCompleted: {
        if (active)
            refresh()
    }

    // backend.revision goes up by one after every import and filter change.
    Connections {
        target: backend
        function onRevisionChanged() {
            if (page.active)
                page.refresh()
        }
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, page.minimumHeight)
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: interactive
        ScrollBar.vertical: ScrollBar { policy: scroller.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Item {
            id: holder
            width: scroller.width - (scroller.interactive ? 12 : 0)    // room for the scroll bar
            height: scroller.contentHeight
            transform: Translate { id: shift }
        }
    }

    ParallelAnimation {
        id: enter
        NumberAnimation { target: holder; property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        NumberAnimation { target: shift; property: "y"; from: 16; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
    }
}
