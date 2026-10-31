#!/bin/bash
# Runs IN the test VM's graphical session with agino-tiling installed (docs/design.md 2.2, 4.5,
# 4.6): turns tiling on for the current desktop with three windows open, then runs every
# shortcut once and prints the active window and all window geometries (wmctrl -lG: client
# area) after each step. Super+arrows are pressed as real keys (xdotool) because DDE routes them
# through dde-daemon and fakewm to KWin's quick tile and maximize actions.
# usage: run-shortcuts.sh
set -u

invoke() {
    dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.invokeShortcut string:"$1" >/dev/null
}
desktop=$(wmctrl -d | awk '$2 == "*" { print $1 }')
state() {
    echo "--- $1 (active: $(xdotool getactivewindow getwindowclassname 2>/dev/null))"
    wmctrl -lGx | awk -v d="$desktop" '$2 == d { printf "%-34s %5d %5d %5d %5d\n", $7, $3, $4, $5, $6 }'
}
step() {
    local label=$1; shift
    "$@"
    sleep 1
    state "$label"
}

start=$(date +%s)
for app in deepin-terminal dde-file-manager deepin-editor; do
    setsid -f "$app" >/dev/null 2>&1
    sleep 2
done
sleep 2
step "tiling on (Meta+Y)" invoke AginoTilingToggle
step "focus next (Meta+J)" invoke AginoTilingFocusNext
step "focus previous (Meta+K)" invoke AginoTilingFocusPrevious
step "move next (Meta+Shift+J)" invoke AginoTilingMoveNext
step "move previous (Meta+Shift+K)" invoke AginoTilingMovePrevious
step "swap with master (Meta+Return)" invoke AginoTilingSwapMaster
step "grow master (Meta+Ctrl+L)" invoke AginoTilingGrowMaster
step "shrink master twice (Meta+Ctrl+H)" bash -c 'for i in 1 2; do dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut string:AginoTilingShrinkMaster >/dev/null; done'
step "next layout: columns (Meta+Space)" invoke AginoTilingNextLayout
step "next layout: monocle (Meta+Space)" invoke AginoTilingNextLayout
step "next layout: master (Meta+Space)" invoke AginoTilingNextLayout
step "monocle on (Meta+F)" invoke AginoTilingMonocle
step "monocle off (Meta+F)" invoke AginoTilingMonocle
step "float the active window (Meta+Shift+Space)" invoke AginoTilingToggleFloat
step "tile it again (Meta+Shift+Space)" invoke AginoTilingToggleFloat
step "real key Super+Right (to the stack)" xdotool key super+Right
step "real key Super+Left (to the master)" xdotool key super+Left
step "real key Super+Up (monocle)" xdotool key super+Up
step "real key Super+Down (back)" xdotool key super+Down
step "real keys Super+Shift+J, Super+J" xdotool key super+shift+j super+j
step "tiling off (Meta+Y)" invoke AginoTilingToggle
echo "--- script log"
journalctl --user --since @"$start" --no-pager | grep -E 'agino-tiling' | sed -E 's/.*qml: //' | cut -c1-200
