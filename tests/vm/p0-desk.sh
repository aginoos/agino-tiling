#!/bin/bash
# Runs IN the test VM's session after p0-run.sh, with the agino-tiling prototype and its dock
# applet loaded (docs/tiling.md 8.1): per-desktop state, KWin quick tile inside a tiled
# desktop, a file dialog, and which global shortcuts already use Meta/Super+Shift.
W() { echo "--- $1"; wmctrl -lGx | awk '$2>=0{printf "d%d %-34s %5d %5d %5d %5d\n", $2, $7, $3, $4, $5, $6}'; }
inv() { dbus-send --session --print-reply --dest=org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut string:"$1" >/dev/null; }
T=$(date +%s)
dbus-send --session --print-reply --dest=org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop uint32:1 string:"桌面 2" >/dev/null
sleep 1; wmctrl -s 1; sleep 1
for a in deepin-terminal deepin-editor; do setsid -f $a >/dev/null 2>&1; sleep 2; done
sleep 2; inv AginoTilingToggle; sleep 1.5
W "desktop 2 tiled, desktop 1 not"
wmctrl -s 0; sleep 1; wmctrl -s 1; sleep 1
inv "Window Quick Tile Left"; sleep 1.5
W "after KWin quick tile left on the active tiled window"
xdotool search --desktop 1 --class deepin-editor windowactivate --sync 2>/dev/null; sleep 0.5
xdotool key ctrl+o; sleep 3
W "with the editor's file dialog open"
xdotool key Escape; sleep 1
echo "--- state reports"
journalctl --user --since @$T --no-pager | grep -E "AGAPPLET state|AGTILE (tiling|added|changed|size)" | sed -E 's/.*(AGAPPLET|AGTILE)/\1/' | cut -c1-150
echo "--- DDE shortcuts with Super"
busctl --user call org.deepin.dde.Keybinding1 /org/deepin/dde/Keybinding1 org.deepin.dde.Keybinding1 ListAllShortcuts |
    grep -oE "<[A-Za-z_]+>(<[A-Za-z_]+>)*[A-Za-z0-9_]+" | sort -u | grep Super | tr '\n' ' '; echo
echo "--- kglobalaccel (KWin) shortcuts with Meta+Shift"
busctl --user call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component allShortcutInfos --json=short |
    python3 -I -c 'import json,sys
for i in json.load(sys.stdin)["data"][0]:
    for k in i[6]:
        if k & 0x10000000 and k & 0x02000000: print(i[4], hex(k & 0x1ffffff))'
