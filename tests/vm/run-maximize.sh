#!/bin/bash
# Runs IN the test VM's graphical session with agino-tiling installed (docs/design.md 4.6, infra
# D-171): presses the real keys Super+Up / Super+Down on the active window, first on a desktop that
# is not tiled (plain maximize / restore through dde-daemon and fakewm), then with tiling on
# (single-window layout on / off). Prints the active window's _NET_WM_STATE and all geometries
# after each key, and the script's log.
# usage: run-maximize.sh
set -u

invoke() {
    dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.invokeShortcut string:"$1" >/dev/null
}
current_desktop_id() {
    dbus-send --session --print-reply --dest=org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get string:org.kde.KWin.VirtualDesktopManager string:current |
        awk -F'"' '/string/ { print $2 }'
}
is_tiled() {
    dbus-send --session --print-reply --dest=org.agino.Tiling1 /org/agino/Tiling1 \
        org.agino.Tiling1.GetTiledDesktops | grep -q "\"$(current_desktop_id)\""
}
desktop=$(wmctrl -d | awk '$2 == "*" { print $1 }')
state() {
    local w
    w=$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $NF}')
    echo "--- $1"
    echo "active $w $(xprop -id "$w" WM_CLASS | sed 's/.*= //') state: $(xprop -id "$w" _NET_WM_STATE | sed 's/.*= //;s/_NET_WM_STATE_//g')"
    wmctrl -lGx | awk -v d="$desktop" '$2 == d { printf "%-34s %5d %5d %5d %5d\n", $7, $3, $4, $5, $6 }'
}
key() {
    xdotool key "$1"
    sleep 1.5
    state "real key $1"
}
click_editor() {
    # windows started from a script are not activated and xdotool's windowactivate is refused: click
    local w X Y WIDTH HEIGHT SCREEN WINDOW
    w=$(xdotool search --onlyvisible --class deepin-editor | tail -1)
    eval "$(xdotool getwindowgeometry --shell "$w")"
    xdotool mousemove $((X + WIDTH / 2)) $((Y + HEIGHT / 2)) click 1
    sleep 1
}

start=$(date +%s)
echo "dde-fakewm: $(pgrep -x dde-fakewm || echo not running)"
pgrep -x deepin-editor >/dev/null || { setsid -f deepin-editor >/dev/null 2>&1; sleep 3; }
pgrep -x deepin-terminal >/dev/null || { setsid -f deepin-terminal >/dev/null 2>&1; sleep 3; }
was_tiled=no
if is_tiled; then was_tiled=yes; invoke AginoTilingToggle; sleep 1.5; fi
echo "desktop $desktop was tiled: $was_tiled"

echo "=== A: not tiled"
click_editor
state "editor clicked"
key super+Up
key super+Down

echo "=== B: tiled"
invoke AginoTilingToggle
sleep 1.5
click_editor
state "tiling on, editor clicked"
key super+Up
key super+Down
key super+Up
invoke AginoTilingMonocle
sleep 1.5
state "Meta+F (leave the single-window layout another way)"

[ "$was_tiled" = yes ] || invoke AginoTilingToggle
echo "--- script log"
journalctl --user --since @"$start" --no-pager | grep -E 'agino-tiling' | sed -E 's/.*qml: //' | cut -c1-200
