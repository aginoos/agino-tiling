#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# xmapwatch.py SECONDS: print MapNotify and the following ConfigureNotify events of top-level
# (frame) windows on :0 for SECONDS seconds, with milliseconds since each window was mapped.
# A tiled window that moves after it was mapped shows up as "CONF ... +NNms" with another
# position: the user can see it appear in one place and jump to its tile (docs/tiling.md 6).
import sys
import time

from Xlib import X, display


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
    d = display.Display()
    root = d.screen().root
    root.change_attributes(event_mask=X.SubstructureNotifyMask)
    mapped = {}
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        while d.pending_events():
            e = d.next_event()
            now = time.monotonic()
            if e.type == X.MapNotify:
                g = e.window.get_geometry()
                mapped[e.window.id] = now
                print(f"MAP  {e.window.id:#x} {g.x},{g.y} {g.width}x{g.height}", flush=True)
            elif e.type == X.ConfigureNotify and e.window.id in mapped:
                dt = (now - mapped[e.window.id]) * 1000
                print(f"CONF {e.window.id:#x} +{dt:.0f}ms {e.x},{e.y} {e.width}x{e.height}", flush=True)
            elif e.type == X.UnmapNotify:
                mapped.pop(e.window.id, None)
        time.sleep(0.002)


if __name__ == "__main__":
    main()
