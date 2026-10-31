// SPDX-License-Identifier: GPL-3.0-or-later
// agino-tiling P0 prototype (docs/tiling.md, D-168): master/stack tiling, switched on and off
// per virtual desktop. Logs carry the AGTILE prefix at warning level so they reach the journal.
import QtQuick
import org.kde.kwin

Item {
    id: root

    property real masterRatio: 0.55
    property int gap: 8
    // desktop id -> true while that desktop tiles
    property var tiledDesktops: ({})
    // desktop id -> window internalIds in layout order (first = master)
    property var order: ({})
    // window internalId -> QRect before it was tiled, restored when tiling ends
    property var savedGeometry: ({})
    // window internalId -> geometry this script last set, to tell our own moves from the user's
    property var placed: ({})

    function log(...args) {
        console.warn("AGTILE", Date.now(), ...args);
    }

    function wid(w) {
        return w.internalId.toString();
    }

    function desktopOf(w) {
        if (w.onAllDesktops || w.desktops.length !== 1)
            return null;
        return w.desktops[0];
    }

    function eligible(w) {
        if (!w.normalWindow || w.transient || w.dialog || w.specialWindow || w.splash || w.utility)
            return false;
        if (w.minimized || w.fullScreen || w.keepAbove || w.skipTaskbar || !w.resizeable || !w.moveable)
            return false;
        if (w.minSize.width > 0 && w.minSize.width === w.maxSize.width && w.minSize.height === w.maxSize.height)
            return false;
        return desktopOf(w) !== null;
    }

    function windowById(id) {
        const all = Workspace.windows;
        for (let i = 0; i < all.length; ++i) {
            if (wid(all[i]) === id)
                return all[i];
        }
        return null;
    }

    // Windows of a desktop on one output, in layout order; drops ids that no longer qualify.
    function tiledWindows(desktop, output) {
        const ids = order[desktop.id] || [];
        const kept = [];
        const result = [];
        for (const id of ids) {
            const w = windowById(id);
            if (!w || !eligible(w) || desktopOf(w).id !== desktop.id)
                continue;
            kept.push(id);
            if (w.output === output)
                result.push(w);
        }
        order[desktop.id] = kept;
        return result;
    }

    function place(w, x, y, width, height) {
        const rect = Qt.rect(Math.round(x), Math.round(y), Math.round(width), Math.round(height));
        placed[wid(w)] = rect;
        w.frameGeometry = rect;
        const got = w.frameGeometry;
        if (got.width !== rect.width || got.height !== rect.height)
            log("size-clamped", w.resourceClass, "asked", rect.width + "x" + rect.height,
                "got", got.width + "x" + got.height, "min", w.minSize.width + "x" + w.minSize.height);
    }

    function layoutOutput(desktop, output) {
        const windows = tiledWindows(desktop, output);
        if (windows.length === 0)
            return;
        const area = Workspace.clientArea(KWin.PlacementArea, output, desktop);
        const x0 = area.x + gap, y0 = area.y + gap;
        const w0 = area.width - 2 * gap, h0 = area.height - 2 * gap;
        if (windows.length === 1) {
            place(windows[0], x0, y0, w0, h0);
            return;
        }
        const masterWidth = Math.round((w0 - gap) * masterRatio);
        place(windows[0], x0, y0, masterWidth, h0);
        const stack = windows.slice(1);
        const sx = x0 + masterWidth + gap, sw = w0 - masterWidth - gap;
        const sh = (h0 - gap * (stack.length - 1)) / stack.length;
        for (let i = 0; i < stack.length; ++i)
            place(stack[i], sx, y0 + i * (sh + gap), sw, sh);
    }

    function layoutDesktop(desktop) {
        if (!desktop || !tiledDesktops[desktop.id])
            return;
        for (const output of Workspace.screens)
            layoutOutput(desktop, output);
    }

    function layoutAll() {
        for (const desktop of Workspace.desktops)
            layoutDesktop(desktop);
    }

    function addWindow(w) {
        const desktop = desktopOf(w);
        if (!desktop || !tiledDesktops[desktop.id] || !eligible(w))
            return false;
        const ids = order[desktop.id] || [];
        if (ids.indexOf(wid(w)) < 0) {
            if (!savedGeometry[wid(w)])
                savedGeometry[wid(w)] = Qt.rect(w.frameGeometry.x, w.frameGeometry.y,
                                                w.frameGeometry.width, w.frameGeometry.height);
            ids.push(wid(w));
            order[desktop.id] = ids;
        }
        return true;
    }

    function setTiling(desktop, on) {
        if (on === !!tiledDesktops[desktop.id])
            return;
        tiledDesktops[desktop.id] = on;
        if (on) {
            order[desktop.id] = [];
            const all = Workspace.stackingOrder;
            for (let i = 0; i < all.length; ++i)
                addWindow(all[i]);
            layoutDesktop(desktop);
        } else {
            for (const id of order[desktop.id] || []) {
                const w = windowById(id);
                if (w && savedGeometry[id])
                    w.frameGeometry = savedGeometry[id];
                delete savedGeometry[id];
                delete placed[id];
            }
            order[desktop.id] = [];
        }
        log("tiling", desktop.name, on ? "on" : "off", "windows", (order[desktop.id] || []).length);
        publishState();
    }

    // Tell the dock button (org.agino.Tiling1 in dde-shell) whether the current desktop tiles.
    function publishState() {
        const desktop = Workspace.currentDesktop;
        log("state", desktop.id, !!tiledDesktops[desktop.id]);
        report.arguments = [desktop.id, !!tiledDesktops[desktop.id]];
        report.call();
    }

    // The tiled window whose rectangle contains point p, other than w.
    function tiledWindowAt(desktop, w, p) {
        for (const id of order[desktop.id] || []) {
            if (id === wid(w))
                continue;
            const r = placed[id];
            if (r && p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height)
                return id;
        }
        return null;
    }

    function trackWindow(w) {
        w.minimizedChanged.connect(() => onWindowChanged(w, "minimized"));
        w.fullScreenChanged.connect(() => onWindowChanged(w, "fullScreen"));
        w.desktopsChanged.connect(() => onWindowChanged(w, "desktops"));
        w.outputChanged.connect(() => onWindowChanged(w, "output"));
        w.interactiveMoveResizeFinished.connect(() => onMoveResizeFinished(w));
    }

    function onWindowChanged(w, why) {
        if (eligible(w))
            addWindow(w);
        log("changed", why, w.resourceClass);
        layoutAll();
    }

    function onMoveResizeFinished(w) {
        const desktop = desktopOf(w);
        if (!desktop || !tiledDesktops[desktop.id])
            return;
        const ids = order[desktop.id] || [];
        const from = ids.indexOf(wid(w));
        if (from < 0)
            return;
        const g = w.frameGeometry;
        const before = placed[wid(w)];
        if (before && from === 0 && g.x === before.x && g.width !== before.width) {
            const area = Workspace.clientArea(KWin.PlacementArea, w.output, desktop);
            masterRatio = Math.min(0.85, Math.max(0.15, (g.width + gap) / (area.width - gap)));
            log("master-ratio", masterRatio.toFixed(2));
        } else {
            const target = tiledWindowAt(desktop, w, Qt.point(g.x + g.width / 2, g.y + g.height / 2));
            if (target) {
                const to = ids.indexOf(target);
                ids[from] = target;
                ids[to] = wid(w);
                log("swap", from, to);
            }
        }
        layoutDesktop(desktop);
    }

    function focusStep(step) {
        const w = Workspace.activeWindow;
        const desktop = Workspace.currentDesktop;
        const ids = order[desktop.id] || [];
        if (!w || ids.length < 2)
            return;
        const i = ids.indexOf(wid(w));
        const next = windowById(ids[((i < 0 ? 0 : i) + step + ids.length) % ids.length]);
        if (next)
            Workspace.activeWindow = next;
    }

    function swapWithMaster() {
        const w = Workspace.activeWindow;
        const desktop = Workspace.currentDesktop;
        const ids = order[desktop.id] || [];
        const i = w ? ids.indexOf(wid(w)) : -1;
        if (i < 0)
            return;
        const target = i === 0 ? 1 : 0;
        if (target >= ids.length)
            return;
        ids[i] = ids[target];
        ids[target] = wid(w);
        layoutDesktop(desktop);
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            trackWindow(w);
            const g = w.frameGeometry;
            if (addWindow(w)) {
                log("added", w.resourceClass, "initial", g.x + "," + g.y + " " + g.width + "x" + g.height);
                layoutDesktop(desktopOf(w));
            }
        }
        function onWindowRemoved(w) {
            delete savedGeometry[wid(w)];
            delete placed[wid(w)];
            layoutAll();
        }
        function onCurrentDesktopChanged() {
            publishState();
        }
        function onScreensChanged() {
            layoutAll();
        }
        function onVirtualScreenGeometryChanged() {
            layoutAll();
        }
    }

    DBusCall {
        id: report
        service: "org.agino.Tiling1"
        path: "/org/agino/Tiling1"
        dbusInterface: "org.agino.Tiling1"
        method: "SetState"
        onFailed: root.log("report failed (dock button not running?)")
    }

    // Invoked by the dock button when it starts, to learn the current state.
    ShortcutHandler {
        name: "AginoTilingPublish"
        text: "agino tiling: report the state to the dock button"
        sequence: ""
        onActivated: root.publishState()
    }

    ShortcutHandler {
        name: "AginoTilingToggle"
        text: "agino tiling: toggle tiling on the current desktop"
        sequence: "Meta+Shift+T"
        onActivated: root.setTiling(Workspace.currentDesktop, !root.tiledDesktops[Workspace.currentDesktop.id])
    }

    ShortcutHandler {
        name: "AginoTilingFocusNext"
        text: "agino tiling: focus the next tiled window"
        sequence: "Meta+Shift+J"
        onActivated: root.focusStep(1)
    }

    ShortcutHandler {
        name: "AginoTilingFocusPrevious"
        text: "agino tiling: focus the previous tiled window"
        sequence: "Meta+Shift+K"
        onActivated: root.focusStep(-1)
    }

    ShortcutHandler {
        name: "AginoTilingSwapMaster"
        text: "agino tiling: swap the active window with the master"
        sequence: "Meta+Shift+Return"
        onActivated: root.swapWithMaster()
    }

    Component.onCompleted: {
        const all = Workspace.windows;
        for (let i = 0; i < all.length; ++i)
            trackWindow(all[i]);
        log("loaded", "desktops", Workspace.desktops.length, "screens", Workspace.screens.length);
        publishState();
    }
}
