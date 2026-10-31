// SPDX-License-Identifier: GPL-3.0-or-later
// agino-tiling (docs/design.md, D-168/D-169): automatic tiling, switched on and off per virtual
// desktop. Layout maths live in ../code/layout.js; this file holds the KWin glue. Logs carry the
// "agino-tiling:" prefix at warning level (info/debug are filtered) and only report state changes
// and anomalies.
import QtQuick
import org.kde.kwin
import "../code/layout.js" as Layout

Item {
    id: root

    // kwinrc [Script-agino-tiling]: gap (pixels) and floatingClasses (comma separated resourceClass)
    property int gap: 8
    property var floatingClasses: []

    // Maps are replaced, never mutated (put/drop). Keys are desktop ids or window internalIds.
    property var tiled: ({})            // desktop id -> true while that desktop tiles
    property var layouts: ({})          // desktop id -> "master" | "columns" | "monocle"
    property var previousLayouts: ({})  // desktop id -> layout before monocle
    property var ratios: ({})           // desktop id -> master width ratio
    property var order: ({})            // desktop id -> window ids in layout order (first = master)
    property var overlapping: ({})      // desktop id -> last layout stacks windows (raise the focused one)
    property var userFloating: ({})     // window id -> true (design 4.1)
    property var saved: ({})            // window id -> geometry before tiling (4.4)
    property var placed: ({})           // window id -> rect this script last set
    property var closing: ({})          // window ids being removed, still listed by Workspace.windows
    property var unmaximized: ({})      // window id -> time we undid its maximize (4.6)
    property var fallbackActive: ({})   // desktop id + output name -> true while 4.3 applies
    property bool busy: false
    property bool reportWarned: false

    function log(...args) {
        console.warn("agino-tiling:", ...args);
    }

    function put(map, key, value) {
        const copy = Object.assign({}, map);
        copy[key] = value;
        return copy;
    }

    function drop(map, key) {
        const copy = Object.assign({}, map);
        delete copy[key];
        return copy;
    }

    function config(key, fallback) {
        try {
            if (typeof KWin.readConfig === "function")
                return KWin.readConfig(key, fallback);
        } catch (e) {
        }
        return fallback;
    }

    // ---- windows and desktops ----

    function wid(w) {
        return w.internalId.toString();
    }

    function desktopOf(w) {
        if (w.onAllDesktops || w.desktops.length !== 1)
            return null;
        return w.desktops[0];
    }

    function desktopById(id) {
        for (const d of Workspace.desktops) {
            if (d.id === id)
                return d;
        }
        return null;
    }

    function windowMap() {
        const map = {};
        for (const w of Workspace.windows) {
            if (!closing[wid(w)])
                map[wid(w)] = w;
        }
        return map;
    }

    function anyTiled() {
        return Object.keys(tiled).length > 0;
    }

    // 4.1 without the transient states (minimized, fullscreen)
    function structural(w) {
        if (!w.normalWindow || w.transient || w.dialog || w.specialWindow || w.splash || w.utility)
            return false;
        if (w.keepAbove || w.skipTaskbar || !w.resizeable || !w.moveable)
            return false;
        if (w.minSize.width > 0 && w.minSize.width === w.maxSize.width && w.minSize.height === w.maxSize.height)
            return false;
        if (userFloating[wid(w)] || floatingClasses.indexOf(w.resourceClass.toLowerCase()) >= 0)
            return false;
        return desktopOf(w) !== null;
    }

    function active(w) {
        return structural(w) && !w.minimized && !w.fullScreen;
    }

    // Windows of a desktop that take part right now, in layout order.
    function members(desktop, output) {
        const map = windowMap();
        const result = [];
        for (const id of order[desktop.id] || []) {
            const w = map[id];
            if (w && active(w) && desktopOf(w).id === desktop.id && (!output || w.output === output))
                result.push(w);
        }
        return result;
    }

    function ids(windows) {
        return windows.map(wid);
    }

    // ---- bookkeeping: which window belongs to which desktop's order ----

    function restore(w, id) {
        if (saved[id] && !w.fullScreen)
            w.frameGeometry = saved[id];
    }

    // Drops ids that closed, left the desktop or stopped qualifying; restores their old geometry.
    function reconcile() {
        const map = windowMap();
        const removed = [];
        let next = {};
        for (const did of Object.keys(order)) {
            const kept = [];
            for (const id of order[did]) {
                const w = map[id];
                if (w && tiled[did] && structural(w) && desktopOf(w).id === did)
                    kept.push(id);
                else
                    removed.push(id);
            }
            next = put(next, did, kept);
        }
        order = next;
        const still = {};
        for (const did of Object.keys(next)) {
            for (const id of next[did])
                still[id] = true;
        }
        for (const id of removed) {
            if (still[id])
                continue;
            if (map[id])
                restore(map[id], id);
            saved = drop(saved, id);
            placed = drop(placed, id);
        }
    }

    function addWindow(w) {
        const desktop = desktopOf(w);
        if (!desktop || !tiled[desktop.id] || !active(w))
            return false;
        const list = order[desktop.id] || [];
        const id = wid(w);
        if (list.indexOf(id) >= 0)
            return true;
        if (w.maximizeMode !== 0) {
            unmaximized = put(unmaximized, id, Date.now());
            w.setMaximize(false, false);
        }
        if (w.tile)
            w.tile = null;
        if (!saved[id]) {
            const g = w.frameGeometry;
            saved = put(saved, id, Qt.rect(g.x, g.y, g.width, g.height));
        }
        order = put(order, desktop.id, list.concat([id]));
        return true;
    }

    // ---- layout ----

    function layoutOf(did) {
        return layouts[did] || "master";
    }

    function ratioOf(did) {
        return ratios[did] || Layout.DEFAULT_RATIO;
    }

    function setLayout(did, name) {
        if (name === "monocle" && layoutOf(did) !== "monocle")
            previousLayouts = put(previousLayouts, did, layoutOf(did));
        layouts = put(layouts, did, name);
        log("layout", did, name);
    }

    function place(w, r) {
        const id = wid(w);
        placed = put(placed, id, r);
        const g = w.frameGeometry;
        if (!w.move && !w.resize && (g.x !== r.x || g.y !== r.y || g.width !== r.width || g.height !== r.height))
            w.frameGeometry = Qt.rect(r.x, r.y, r.width, r.height);
    }

    function layoutOutput(desktop, output) {
        const windows = members(desktop, output);
        if (windows.length === 0)
            return;
        const area = Workspace.clientArea(KWin.PlacementArea, output, desktop);
        const none = windows.map(() => ({ minWidth: 0, minHeight: 0 }));
        let result = Layout.arrange(layoutOf(desktop.id), area, gap, ratioOf(desktop.id), none);
        for (let i = 0; i < windows.length; ++i)
            place(windows[i], result.rects[i]);
        // KWin does not enforce the declared minimum size of most X11 windows (DTK ones included), so
        // only a size it actually kept larger than the cell overlaps a neighbour (design.md 4.3)
        const enforced = windows.map((w, i) => {
            const g = w.frameGeometry, r = result.rects[i];
            return g.width > r.width + 1 || g.height > r.height + 1 ? { minWidth: g.width, minHeight: g.height }
                                                                   : { minWidth: 0, minHeight: 0 };
        });
        if (enforced.some(m => m.minWidth > 0))
            result = Layout.arrange(layoutOf(desktop.id), area, gap, ratioOf(desktop.id), enforced);
        const key = desktop.id + "@" + output.name;
        if (result.fallback !== !!fallbackActive[key]) {
            fallbackActive = result.fallback ? put(fallbackActive, key, true) : drop(fallbackActive, key);
            if (result.fallback)
                log("minimum sizes do not fit, stacking windows on", output.name, windows.length, "windows");
        }
        if (result.fallback) {
            for (let i = 0; i < windows.length; ++i)
                place(windows[i], result.rects[i]);
        }
        const stacked = result.fallback || layoutOf(desktop.id) === "monocle";
        overlapping = put(overlapping, desktop.id, stacked);
        const focus = Workspace.activeWindow;
        if (stacked && focus && windows.indexOf(focus) >= 0)
            Workspace.raiseWindow(focus);
    }

    function layoutDesktop(desktop) {
        if (!desktop || !tiled[desktop.id])
            return;
        if (busy) {
            settle.restart();
            return;
        }
        busy = true;
        try {
            for (const output of Workspace.screens)
                layoutOutput(desktop, output);
        } finally {
            busy = false;
        }
    }

    function layoutAll() {
        for (const desktop of Workspace.desktops)
            layoutDesktop(desktop);
    }

    // ---- switching tiling on and off ----

    function setTiling(desktop, on, byUser) {
        if (on === !!tiled[desktop.id])
            return;
        if (on) {
            tiled = put(tiled, desktop.id, true);
            order = put(order, desktop.id, []);
            const all = Workspace.stackingOrder;
            for (let i = all.length - 1; i >= 0; --i)
                addWindow(all[i]);
            layoutDesktop(desktop);
        } else {
            const map = windowMap();
            for (const id of order[desktop.id] || []) {
                if (map[id])
                    restore(map[id], id);
                saved = drop(saved, id);
                placed = drop(placed, id);
            }
            tiled = drop(tiled, desktop.id);
            order = drop(order, desktop.id);
            layouts = drop(layouts, desktop.id);
            overlapping = drop(overlapping, desktop.id);
        }
        log("tiling", desktop.name, on ? "on" : "off", "windows", (order[desktop.id] || []).length);
        if (byUser)
            tilingChanged(desktop);
        publishCurrent();
    }

    function toggleCurrent() {
        const desktop = Workspace.currentDesktop;
        setTiling(desktop, !tiled[desktop.id], true);
    }

    // ---- D-Bus protocol with the dock applet (design 2.1, 2.3) ----

    function publishCurrent() {
        const desktop = Workspace.currentDesktop;
        currentChangedCall.arguments = [desktop.id, !!tiled[desktop.id]];
        currentChangedCall.call();
    }

    function tilingChanged(desktop) {
        tilingChangedCall.arguments = [desktop.id, !!tiled[desktop.id]];
        tilingChangedCall.call();
    }

    function sync() {
        getTiledCall.call();
    }

    // Only turns desktops on; never turns one off (the user may have just switched it on).
    function applyTiledList(list) {
        for (let i = 0; i < list.length; ++i) {
            const desktop = desktopById(list[i]);
            if (desktop)
                setTiling(desktop, true, false);
        }
        publishCurrent();
    }

    // ---- window events ----

    function trackWindow(w) {
        const changed = () => onWindowChanged(w);
        w.minimizedChanged.connect(changed);
        w.fullScreenChanged.connect(changed);
        w.desktopsChanged.connect(changed);
        w.outputChanged.connect(changed);
        w.keepAboveChanged.connect(changed);
        w.skipTaskbarChanged.connect(changed);
        w.tileChanged.connect(() => onTileChanged(w));
        w.maximizedChanged.connect(() => onMaximizedChanged(w));
        w.interactiveMoveResizeFinished.connect(() => onMoveResizeFinished(w));
    }

    function onWindowChanged(w) {
        if (!anyTiled())
            return;
        const desktop = desktopOf(w);
        if (desktop && tiled[desktop.id])
            addWindow(w);
        reconcile();
        settle.restart();
    }

    function inTiledOrder(w) {
        const desktop = desktopOf(w);
        return desktop && tiled[desktop.id] && (order[desktop.id] || []).indexOf(wid(w)) >= 0 ? desktop : null;
    }

    // 4.6: quick tile to the left half -> master, to the right half -> first stack slot.
    function onTileChanged(w) {
        const desktop = w.tile ? inTiledOrder(w) : null;
        if (!desktop)
            return;
        const centre = w.tile.relativeGeometry.x + w.tile.relativeGeometry.width / 2;
        const width = w.tile.relativeGeometry.width;
        w.tile = null;
        if (width < 0.9) {
            const same = members(desktop, w.output);
            const moved = Layout.moveTo(ids(same), wid(w), centre < 0.5 ? 0 : 1);
            order = put(order, desktop.id, Layout.applyMemberOrder(order[desktop.id], moved));
        }
        log("quick tile taken over", w.resourceClass, centre < 0.5 ? "left" : "right");
        layoutDesktop(desktop);
        settle.restart();
    }

    // 4.6: maximize -> single-window layout; unmaximize while in it -> previous layout.
    function onMaximizedChanged(w) {
        const desktop = inTiledOrder(w);
        if (!desktop)
            return;
        const did = desktop.id;
        if (w.maximizeMode !== 0) {
            unmaximized = put(unmaximized, wid(w), Date.now());
            w.setMaximize(false, false);
            if (layoutOf(did) !== "monocle")
                setLayout(did, "monocle");
            Workspace.activeWindow = w;
        } else if (Date.now() - (unmaximized[wid(w)] || 0) > 800 && layoutOf(did) === "monocle") {
            setLayout(did, previousLayouts[did] || "master");
        } else {
            return;
        }
        layoutDesktop(desktop);
        settle.restart();
    }

    // 4.5: drop on another tiled window swaps; right-edge resize of the master sets the ratio.
    function onMoveResizeFinished(w) {
        const desktop = inTiledOrder(w);
        if (!desktop)
            return;
        const did = desktop.id;
        const id = wid(w);
        const g = w.frameGeometry;
        const before = placed[id];
        const same = members(desktop, w.output);
        const sameIds = ids(same);
        if (before && (g.width !== before.width || g.height !== before.height)) {
            if (layoutOf(did) === "master" && same.length > 1 && sameIds[0] === id && Math.abs(g.x - before.x) <= 2) {
                const area = Workspace.clientArea(KWin.PlacementArea, w.output, desktop);
                ratios = put(ratios, did, Layout.ratioFromWidth(g.width, area, gap));
                log("master ratio", ratioOf(did).toFixed(2));
            }
        } else if (layoutOf(did) !== "monocle" && !overlapping[did]) {
            const rects = sameIds.map(i => placed[i]);
            const target = Layout.indexAt(rects, g.x + g.width / 2, g.y + g.height / 2, sameIds.indexOf(id));
            if (target >= 0) {
                const swapped = Layout.swap(sameIds, sameIds.indexOf(id), target);
                order = put(order, did, Layout.applyMemberOrder(order[did], swapped));
            }
        }
        layoutDesktop(desktop);
    }

    // ---- shortcut actions (design 2.2) ----

    function currentMembers() {
        return members(Workspace.currentDesktop, null);
    }

    function focusStep(step) {
        const list = currentMembers();
        if (list.length < 2)
            return;
        const i = list.indexOf(Workspace.activeWindow);
        const next = list[Layout.wrapIndex(list.length, i < 0 ? 0 : i, step)];
        Workspace.activeWindow = next;
    }

    // Applies fn(ids of the active window's output, id) -> new ids to the active tiled window.
    function reorderActive(fn) {
        const w = Workspace.activeWindow;
        const desktop = Workspace.currentDesktop;
        if (!w || !tiled[desktop.id])
            return;
        const same = ids(members(desktop, w.output));
        if (same.indexOf(wid(w)) < 0)
            return;
        order = put(order, desktop.id, Layout.applyMemberOrder(order[desktop.id], fn(same, wid(w))));
        layoutDesktop(desktop);
    }

    function adjustRatio(delta) {
        const did = Workspace.currentDesktop.id;
        if (!tiled[did])
            return;
        ratios = put(ratios, did, Layout.clampRatio(ratioOf(did) + delta));
        layoutDesktop(Workspace.currentDesktop);
    }

    function nextLayout() {
        const desktop = Workspace.currentDesktop;
        if (!tiled[desktop.id])
            return;
        setLayout(desktop.id, Layout.nextLayout(layoutOf(desktop.id)));
        layoutDesktop(desktop);
    }

    function toggleMonocle() {
        const desktop = Workspace.currentDesktop;
        if (!tiled[desktop.id])
            return;
        const did = desktop.id;
        setLayout(did, layoutOf(did) === "monocle" ? (previousLayouts[did] || "master") : "monocle");
        layoutDesktop(desktop);
    }

    function toggleFloat() {
        const w = Workspace.activeWindow;
        const desktop = Workspace.currentDesktop;
        if (!w || !tiled[desktop.id])
            return;
        const id = wid(w);
        if (userFloating[id]) {
            userFloating = drop(userFloating, id);
            addWindow(w);
        } else if (structural(w)) {
            userFloating = put(userFloating, id, true);
            reconcile();
        } else {
            return;
        }
        log("float", w.resourceClass, !!userFloating[id]);
        layoutDesktop(desktop);
    }

    Timer {
        id: settle
        interval: 50
        onTriggered: {
            root.closing = ({});
            root.reconcile();
            root.layoutAll();
        }
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            root.trackWindow(w);
            const desktop = root.desktopOf(w);
            if (root.anyTiled() && root.addWindow(w)) {
                root.layoutDesktop(desktop);
                settle.restart();
            }
        }
        function onWindowRemoved(w) {
            const id = root.wid(w);
            root.closing = root.put(root.closing, id, true);
            root.userFloating = root.drop(root.userFloating, id);
            root.unmaximized = root.drop(root.unmaximized, id);
            root.reconcile();
            root.layoutAll();
            settle.restart();
        }
        function onWindowActivated(w) {
            const desktop = w ? root.desktopOf(w) : null;
            if (desktop && root.overlapping[desktop.id] && root.members(desktop, w.output).indexOf(w) >= 0)
                Workspace.raiseWindow(w);
        }
        function onCurrentDesktopChanged() {
            root.publishCurrent();
        }
        function onDesktopsChanged() {
            for (const did of Object.keys(root.tiled)) {
                if (!root.desktopById(did)) {
                    root.tiled = root.drop(root.tiled, did);
                    root.order = root.drop(root.order, did);
                }
            }
            root.layoutAll();
            root.publishCurrent();
        }
        function onScreensChanged() {
            settle.restart();
        }
        function onVirtualScreenGeometryChanged() {
            settle.restart();
        }
    }

    DBusCall {
        id: currentChangedCall
        service: "org.agino.Tiling1"
        path: "/org/agino/Tiling1"
        dbusInterface: "org.agino.Tiling1"
        method: "CurrentChanged"
        onFailed: {
            if (!root.reportWarned) {
                root.reportWarned = true;
                root.log("dock applet not reachable (org.agino.Tiling1); button state not updated");
            }
        }
    }

    DBusCall {
        id: tilingChangedCall
        service: "org.agino.Tiling1"
        path: "/org/agino/Tiling1"
        dbusInterface: "org.agino.Tiling1"
        method: "TilingChanged"
    }

    // The applet may not be running yet at login; it calls AginoTilingSync when it is.
    DBusCall {
        id: getTiledCall
        service: "org.agino.Tiling1"
        path: "/org/agino/Tiling1"
        dbusInterface: "org.agino.Tiling1"
        method: "GetTiledDesktops"
        onFinished: returnValue => root.applyTiledList(returnValue.length > 0 ? returnValue[0] : [])
    }

    ShortcutHandler {
        name: "AginoTilingToggle"
        text: "agino tiling: toggle tiling on the current desktop"
        sequence: "Meta+Y"
        onActivated: root.toggleCurrent()
    }

    ShortcutHandler {
        name: "AginoTilingFocusNext"
        text: "agino tiling: focus the next tiled window"
        sequence: "Meta+J"
        onActivated: root.focusStep(1)
    }

    ShortcutHandler {
        name: "AginoTilingFocusPrevious"
        text: "agino tiling: focus the previous tiled window"
        sequence: "Meta+K"
        onActivated: root.focusStep(-1)
    }

    ShortcutHandler {
        name: "AginoTilingMoveNext"
        text: "agino tiling: swap the active window with the next one"
        sequence: "Meta+Shift+J"
        onActivated: root.reorderActive((list, id) => Layout.moveBy(list, id, 1))
    }

    ShortcutHandler {
        name: "AginoTilingMovePrevious"
        text: "agino tiling: swap the active window with the previous one"
        sequence: "Meta+Shift+K"
        onActivated: root.reorderActive((list, id) => Layout.moveBy(list, id, -1))
    }

    ShortcutHandler {
        name: "AginoTilingSwapMaster"
        text: "agino tiling: swap the active window with the master"
        sequence: "Meta+Return"
        onActivated: root.reorderActive((list, id) => Layout.swapMaster(list, id))
    }

    ShortcutHandler {
        name: "AginoTilingShrinkMaster"
        text: "agino tiling: shrink the master area"
        sequence: "Meta+Ctrl+H"
        onActivated: root.adjustRatio(-0.05)
    }

    ShortcutHandler {
        name: "AginoTilingGrowMaster"
        text: "agino tiling: grow the master area"
        sequence: "Meta+Ctrl+L"
        onActivated: root.adjustRatio(0.05)
    }

    ShortcutHandler {
        name: "AginoTilingNextLayout"
        text: "agino tiling: next layout"
        sequence: "Meta+Space"
        onActivated: root.nextLayout()
    }

    ShortcutHandler {
        name: "AginoTilingMonocle"
        text: "agino tiling: single window layout on/off"
        sequence: "Meta+F"
        onActivated: root.toggleMonocle()
    }

    ShortcutHandler {
        name: "AginoTilingToggleFloat"
        text: "agino tiling: float or tile the active window"
        sequence: "Meta+Shift+Space"
        onActivated: root.toggleFloat()
    }

    // Invoked by the dock applet when it starts.
    ShortcutHandler {
        name: "AginoTilingSync"
        text: "agino tiling: re-read the tiled desktops from the dock applet"
        sequence: ""
        onActivated: root.sync()
    }

    Component.onCompleted: {
        root.gap = parseInt(config("gap", 8));
        if (isNaN(root.gap) || root.gap < 0)
            root.gap = 8;
        root.floatingClasses = String(config("floatingClasses", "")).split(",")
            .map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
        for (const w of Workspace.windows)
            trackWindow(w);
        log("loaded", "desktops", Workspace.desktops.length, "screens", Workspace.screens.length,
            "gap", gap, "floating classes", floatingClasses.length);
        sync();
        publishCurrent();
    }
}
