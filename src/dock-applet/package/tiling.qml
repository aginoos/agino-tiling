// SPDX-License-Identifier: GPL-3.0-or-later
// Dock button that switches tiling on the current workspace (modeled on dde-shell's multitaskview.qml).
import QtQuick 2.15
import QtQuick.Controls 2.15

import org.deepin.ds 1.0
import org.deepin.dtk 1.0 as D
import org.deepin.ds.dock 1.0

AppletDockItem {
    id: tiling
    dockOrder: 14

    Accessible.role: Accessible.Button
    Accessible.name: toolTip.text

    PanelToolTip {
        id: toolTip
        readonly property string stateText: Applet.tiling ? qsTr("Tiling: on") : qsTr("Tiling: off")
        text: Applet.toggleKey ? qsTr("%1 (%2)").arg(stateText).arg(Applet.toggleKey) : stateText
        toolTipX: DockPanelPositioner.x
        toolTipY: DockPanelPositioner.y
    }

    D.DciIcon {
        anchors.centerIn: parent
        name: Applet.iconName
        scale: Panel.rootObject.dockItemMaxSize * 9 / 14 / Dock.MAX_DOCK_TASKMANAGER_ICON_SIZE
        sourceSize: Qt.size(Dock.MAX_DOCK_TASKMANAGER_ICON_SIZE, Dock.MAX_DOCK_TASKMANAGER_ICON_SIZE)
    }

    Timer {
        id: toolTipShowTimer
        interval: 50
        onTriggered: {
            var point = tiling.mapToItem(null, tiling.width / 2, tiling.height / 2)
            toolTip.DockPanelPositioner.bounding = Qt.rect(point.x, point.y, toolTip.width, toolTip.height)
            toolTip.open()
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.WithinBounds
        onTapped: {
            Applet.toggle()
            toolTip.close()
        }
    }

    TapHandler {
        acceptedButtons: Qt.NoButton
        acceptedDevices: PointerDevice.TouchScreen
        gesturePolicy: TapHandler.WithinBounds
        onTapped: {
            Applet.toggle()
            toolTip.close()
        }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                Applet.refreshToggleKey()
                toolTipShowTimer.start()
            } else {
                if (toolTipShowTimer.running)
                    toolTipShowTimer.stop()
                toolTip.close()
            }
        }
    }
}
