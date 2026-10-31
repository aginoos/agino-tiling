#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the DDE shortcut definitions of agino-tiling (docs/design.md 2.2) into this directory.

dde-services' shortcut service (dde-services src/plugin-qt/shortcut/DEVELOPER_GUIDE.md) loads
agino-tiling.ini and one DConfig file per shortcut, grabs the keys, shows them in the Control
Center (category "Tiling", the user can change the keys) and runs triggerValue on a key press.
The command invokes the KWin script's action of the same meaning through kglobalaccel; the
script's actions have no keys of their own. Run it after changing SHORTCUTS and commit the output.
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP_ID = "agino-tiling"
CATEGORY = "Tiling"
PRESS, RELEASE, PRESS_REPEAT = 1, 2, 5

# name, KWin script action, display name, default key, key event flags
SHORTCUTS = [
    ("toggle", "AginoTilingToggle", "Tiling on/off", "Meta+Y", RELEASE),
    ("focus-next", "AginoTilingFocusNext", "Focus the next window", "Meta+J", PRESS),
    ("focus-previous", "AginoTilingFocusPrevious", "Focus the previous window", "Meta+K", PRESS),
    ("move-next", "AginoTilingMoveNext", "Swap with the next window", "Meta+Shift+J", PRESS),
    ("move-previous", "AginoTilingMovePrevious", "Swap with the previous window", "Meta+Shift+K", PRESS),
    ("swap-master", "AginoTilingSwapMaster", "Swap with the master window", "Meta+Return", PRESS),
    ("shrink-master", "AginoTilingShrinkMaster", "Shrink the master area", "Meta+Ctrl+H", PRESS_REPEAT),
    ("grow-master", "AginoTilingGrowMaster", "Grow the master area", "Meta+Ctrl+L", PRESS_REPEAT),
    ("next-layout", "AginoTilingNextLayout", "Next layout", "Meta+Space", RELEASE),
    ("monocle", "AginoTilingMonocle", "Single window layout on/off", "Meta+F", RELEASE),
    ("float", "AginoTilingToggleFloat", "Float or tile the window", "Meta+Shift+Space", RELEASE),
]


def key(name, value, description, permissions=""):
    return {"value": value, "serial": 0, "flags": [], "name": name, "description": description,
            "permissions": permissions, "visibility": "private"}


def config(order, action, display_name, hotkey, flags):
    invoke = ["/usr/bin/dbus-send", "--session", "--type=method_call", "--dest=org.kde.kglobalaccel",
              "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", f"string:{action}"]
    return {
        "magic": "dsg.config.meta",
        "version": "1.0",
        "contents": {
            "appId": key("appId", APP_ID, "provider of the shortcut"),
            "displayName": key("displayName", display_name, "name shown in the Control Center"),
            "displayOrder": key("displayOrder", order, "display order within the category"),
            "hotkeys": key("hotkeys", [hotkey], "key combinations", "readwrite"),
            "keyEventFlags": key("keyEventFlags", flags, "1=press, 2=release, 4=repeat"),
            "triggerType": key("triggerType", 1, "command"),
            "triggerValue": key("triggerValue", invoke, f"invoke the KWin script action {action}"),
            "category": key("category", CATEGORY, "category in the Control Center"),
            "enabled": key("enabled", True, "shortcut enabled", "readwrite"),
            "modifiable": key("modifiable", True, "the user can change the keys"),
        },
    }


def main():
    sub_paths = []
    for i, (name, action, display_name, hotkey, flags) in enumerate(SHORTCUTS):
        sub_path = f"{APP_ID}.shortcut.{name}"
        sub_paths.append(sub_path)
        out = HERE / "configs" / sub_path / "org.deepin.shortcut.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(config((i + 1) * 10, action, display_name, hotkey, flags), indent=4) + "\n")
    # QSettings list (comma separated) like the service's own .ini files: DEVELOPER_GUIDE.md says ";",
    # but QSettings reads ";" as the start of a comment and the service then sees only the first path
    (HERE / f"{APP_ID}.ini").write_text("[Config]\nSubPaths=" + ",".join(sub_paths) + "\n")


if __name__ == "__main__":
    main()
