// SPDX-License-Identifier: GPL-3.0-or-later
// P0 prototype (docs/tiling.md 8.1): dock button that switches tiling on the current desktop.
// Filled square = tiling on. Logs its position and taps (AGAPPLET) to the journal.
import QtQuick 2.15
import QtQuick.Controls 2.15

import org.deepin.ds 1.0
import org.deepin.dtk 1.0 as D
import org.deepin.ds.dock 1.0

AppletDockItem {
    id: tiling
    dockOrder: 14

    function logPosition(tag) {
        const p = tiling.mapToGlobal(tiling.width / 2, tiling.height / 2)
        const w = tiling.Window.window
        console.warn("AGAPPLET", tag, "center", Math.round(p.x), Math.round(p.y),
                     "size", Math.round(tiling.width), Math.round(tiling.height), "visible", tiling.visible,
                     "window", w ? (w.x + "," + w.y + " " + w.width + "x" + w.height) : "none")
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6
        radius: 4
        color: Applet.tiling ? border.color : "transparent"
        border.width: 2
        border.color: D.DTK.themeType === D.ApplicationHelper.DarkType ? "white" : "black"
        Text {
            anchors.centerIn: parent
            text: "T"
            color: Applet.tiling ? (D.DTK.themeType === D.ApplicationHelper.DarkType ? "black" : "white") : parent.border.color
        }
    }

    HoverHandler {
        onHoveredChanged: if (hovered) tiling.logPosition("hovered")
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            tiling.logPosition("tapped")
            Applet.toggle()
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: tiling.logPosition("placed")
    }
}
