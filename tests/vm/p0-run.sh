#!/bin/bash
# Runs IN the test VM's graphical session (DISPLAY, DBUS_SESSION_BUS_ADDRESS set): P0 checks for
# a tiling KWin script (docs/tiling.md 8.1). Prints window geometries (wmctrl -lG: client area)
# before tiling, after turning it on, after new windows open, and after turning it off, plus the
# MapNotify/ConfigureNotify timing of the new windows (xmapwatch.py) and the script's log.
# usage: p0-run.sh TOGGLE_SHORTCUT [NEW_APPS...]
#   TOGGLE_SHORTCUT  kglobalaccel name of the script's on/off action in component "kwin"
#   NEW_APPS         commands opened while tiling is on (default: deepin-system-monitor deepin-calculator)
# env TOGGLE_OFF: a separate action that turns tiling off (Krohnkite: KrohnkiteFloatingLayout);
#   it is also invoked once at the start so the "before" state is floating.
set -u
here=$(dirname "$(readlink -f "$0")")
toggle=$1; shift
off=${TOGGLE_OFF:-$toggle}
new_apps=("$@")
[ ${#new_apps[@]} -gt 0 ] || new_apps=(deepin-system-monitor deepin-calculator)

invoke() {
    dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.invokeShortcut string:"$1" >/dev/null
}
windows() {
    echo "--- $1"
    wmctrl -lGx | awk '$2 == 0 { printf "%-40s %5d %5d %5d %5d\n", $7, $3, $4, $5, $6 }'
}

start=$(date +%s)
[ -z "${TOGGLE_OFF:-}" ] || invoke "$off"
for app in deepin-terminal dde-file-manager deepin-editor dde-control-center; do
    setsid -f "$app" >/dev/null 2>&1
    sleep 1.5
done
sleep 4
windows "before"
invoke "$toggle"
sleep 1.5
windows "tiling on"
python3 -I "$here/xmapwatch.py" $((4 * ${#new_apps[@]} + 3)) > /tmp/p0-xmap.txt &
watcher=$!
sleep 0.5
for app in "${new_apps[@]}"; do
    setsid -f "$app" >/dev/null 2>&1
    sleep 4
done
wait "$watcher"
echo "--- X events of new windows"
cat /tmp/p0-xmap.txt
windows "after new windows"
invoke "$off"
sleep 1.5
windows "tiling off"
echo "--- script log"
journalctl --user --since @"$start" --no-pager | grep -E 'AGTILE|KROHNKITE|qml:' | cut -c1-240 | tail -40
