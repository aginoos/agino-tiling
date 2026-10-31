#!/bin/bash
# Runs IN the test VM's graphical session with agino-tiling installed (docs/design.md 2.2): presses
# every shortcut as a real key and shows that dde-services' shortcut service reports it
# (ShortcutActivated) and invokes the KWin script action (kglobalaccel invokeShortcut), with the
# window geometries after each key. Then holds a repeating key, and changes the on/off key through
# the service (ModifyHotkeys) and back.
# usage: run-ddekeys.sh
set -u

svc() {
    busctl --user --json=short call org.deepin.dde.Keybinding1 /org/deepin/dde/Keybinding1 org.deepin.dde.Keybinding1 "$@"
}
desktop=$(wmctrl -d | awk '$2 == "*" { print $1 }')
geometry() {
    wmctrl -lGx | awk -v d="$desktop" '$2 == d { printf "%s %d,%d %dx%d; ", $7, $3, $4, $5, $6 }'
    echo
}
monitor_log=$(mktemp)
# line buffered and appending: the log is emptied after each key while dbus-monitor keeps writing
stdbuf -oL dbus-monitor --session "type='signal',interface='org.deepin.dde.Keybinding1',member='ShortcutActivated'" \
    "type='method_call',interface='org.kde.kglobalaccel.Component',member='invokeShortcut'" >> "$monitor_log" 2>&1 &
monitor=$!
sleep 1
events() {
    # one line per event: the signal's shortcut id or the invoked action
    grep -a -A1 -E 'member=(ShortcutActivated|invokeShortcut)' "$monitor_log" | grep -oE 'string "[^"]+"' | sed 's/string //' | tr '\n' ' '
    : > "$monitor_log"
}
key() {
    xdotool key "$1"
    sleep 1.2
    echo "--- $1: $(events)"
    echo "    $(geometry)"
}

for app in deepin-terminal dde-file-manager deepin-editor; do
    pgrep -f "$app" >/dev/null || { setsid -f "$app" >/dev/null 2>&1; sleep 2; }
done
sleep 2
current=$(dbus-send --session --print-reply --dest=org.kde.KWin /VirtualDesktopManager \
    org.freedesktop.DBus.Properties.Get string:org.kde.KWin.VirtualDesktopManager string:current | awk -F'"' '/string/ { print $2 }')
if dbus-send --session --print-reply --dest=org.agino.Tiling1 /org/agino/Tiling1 org.agino.Tiling1.GetTiledDesktops |
        grep -q "\"$current\""; then
    # start untiled, so that the first Super+Y turns tiling on
    dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin \
        org.kde.kglobalaccel.Component.invokeShortcut string:AginoTilingToggle >/dev/null
    sleep 1.5
fi
: > "$monitor_log"
echo "--- start: $(geometry)"
key super+y
xdotool mousemove 100 400 click 1; sleep 1; : > "$monitor_log"
for k in super+j super+k super+shift+j super+shift+k super+Return super+ctrl+l super+ctrl+h \
         super+space super+space super+space super+f super+f super+shift+space super+shift+space; do
    key "$k"
done

echo "=== hold Super+Ctrl+L for 2 s (press + repeat)"
xdotool keydown super+ctrl+l; sleep 2; xdotool keyup super+ctrl+l; sleep 1
echo "invocations: $(events | grep -o AginoTilingGrowMaster | wc -l)  $(geometry)"
xdotool keydown super+ctrl+h; sleep 2; xdotool keyup super+ctrl+h; sleep 1
echo "invocations: $(events | grep -o AginoTilingShrinkMaster | wc -l)  $(geometry)"

echo "=== change the on/off key to Super+U through the service, then back"
svc ModifyHotkeys sas agino-tiling.shortcut.toggle 1 "Meta+U"
svc GetShortcut s agino-tiling.shortcut.toggle
key super+y
key super+u
key super+u
svc ModifyHotkeys sas agino-tiling.shortcut.toggle 1 "Meta+Y"
svc GetShortcut s agino-tiling.shortcut.toggle
key super+y

kill "$monitor"
rm -f "$monitor_log"
