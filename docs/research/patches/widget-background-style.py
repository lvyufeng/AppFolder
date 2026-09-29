#!/usr/bin/env python3
"""Flip a widget's `backgroundStyle` in the simulator's chronod descriptor cache.

Why this exists
---------------
`WidgetBackgroundStyle` (transparent / blur / opaque) is the knob that decides
whether a widget's plate transmits the wallpaper. It is set by the private SPI
`WidgetConfiguration.backgroundStyle(_:)`, which is exported in `WidgetKit.tbd`
but has no `@available` annotation, so no Swift call site with a deployment
target of 18 can reference it — verified by compiling it (see
`docs/research/04-实现笔记.md`). So the only way to *see* the style in action is
to write it where the system reads it.

Measured on the simulator, paired regression against the bare wallpaper at the
same coordinate (the plate region x 110-1100 / y 1520-1950, corner rim excluded):

    0   flat (255,255,255)          gain -0.056, r -0.069   — no wallpaper in it
    1   gain +0.998, r +0.996       vs the *unblurred* wallpaper; 4.5% of plate
                                    pixels differ from bare by more than 1
    2   gain +0.613, r +0.970       vs the wallpaper blurred by sigma 4, r² 0.940

Value 2 is the cell WidgetLoft occupies on the real phone (0.612 / +0.988).
Value 1 is what "liquid glass" looks like when it is not frosted.

**This is the only knob.** It is a per-widget, per-device decision made when the
widget is added, cached in the descriptor; nothing an app ships changes it. On a
phone the DB is on the system partition and unreachable from the host — see the
2026-09-29 device section of `04-实现笔记.md` for what was tried.

Where the system reads it
-------------------------
`~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/chronod/chrono.sql`,
table `Descriptors(bundleIdentifier TEXT PRIMARY KEY, data BLOB, reloadRequired
INTEGER, descriptorType INTEGER)`. `data` is an `NSKeyedArchiver` binary plist;
the root `CHSWidgetDescriptor` object is `$objects[2]`, and its `backgroundStyle`
is a **plain int**, not a `UID` reference. Observed values: ours 0,
`BatteriesAvocadoWidgetExtension` and `PeopleWidget-iOS` 2.

Because chronod caches this in SQLite, editing an `Info.plist` or reinstalling
the extension does not change it — the descriptor survives. This script is the
only lever, and it is for **investigation only**: it is not, and cannot become,
something the app does.

Usage
-----
    python3 widget-background-style.py [style] [--device UDID] [--bundle SUBSTR]

`style` defaults to 2 (blur). Pass 0 to put it back. A `.bak-before-bgstyle`
copy of the database is written on the first run and never overwritten, so
recovery does not depend on remembering the original value.

After running, reboot the simulator (`xcrun simctl shutdown` / `boot`) or
SpringBoard and chronod keep serving the cached blob. Then screenshot the Home
Screen and measure the plate against the wallpaper with the paired-pixel method
described in `04-实现笔记.md`.
"""

import argparse
import os
import plistlib
import shutil
import sqlite3
import sys

DEFAULT_UDID = "F022B294-03B2-4902-BA12-D1D9563DCA35"  # the "AppFolder Test" simulator
DEFAULT_BUNDLE_SUBSTR = "lvyufeng"  # com.lvyufeng.appfolder.widget


def database_path(udid: str) -> str:
    data = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data")
    if not os.path.isdir(data):
        sys.exit(f"no simulator data directory for {udid}")
    return os.path.join(data, "Library/chronod/chrono.sql")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("style", nargs="?", type=int, default=1,
                        help="new backgroundStyle, measured in the simulator: "
                             "0 = flat white plate (what our widget ships with); "
                             "1 = clear glass — a 1:1 copy of the wallpaper at the same "
                             "coordinate, pair-regressed gain +0.998 / r +0.996, only "
                             "4.5%% of plate pixels off the bare wallpaper by more than 1; "
                             "2 = frosted glass, gain +0.613 / r +0.970 against the "
                             "wallpaper blurred by sigma 4, r^2 0.940")
    parser.add_argument("--device", default=DEFAULT_UDID)
    parser.add_argument("--bundle", default=DEFAULT_BUNDLE_SUBSTR,
                        help="substring of the extension's bundle identifier")
    args = parser.parse_args()

    db = database_path(args.device)
    backup = db + ".bak-before-bgstyle"
    if not os.path.exists(backup):
        shutil.copy2(db, backup)
        print(f"backed up -> {backup}")

    con = sqlite3.connect(db)
    row = con.execute(
        "SELECT rowid, bundleIdentifier, data FROM Descriptors "
        "WHERE CAST(bundleIdentifier AS TEXT) LIKE ?;",
        (f"%{args.bundle}%",),
    ).fetchone()
    if row is None:
        sys.exit(f"no descriptor matching {args.bundle!r}; is the widget on the Home Screen?")

    rowid, bundle, blob = row
    descriptor = plistlib.loads(blob)
    root = descriptor["$objects"][2]
    if "backgroundStyle" not in root:
        sys.exit(f"{bundle}: descriptor has no backgroundStyle key")

    key = root["backgroundStyle"]
    old = descriptor["$objects"][key.data] if isinstance(key, plistlib.UID) else key
    if old == args.style:
        print(f"{bundle}: backgroundStyle already {args.style}, nothing to do")
        return

    root["backgroundStyle"] = args.style
    con.execute("UPDATE Descriptors SET data = ? WHERE rowid = ?;",
                (plistlib.dumps(descriptor, fmt=plistlib.FMT_BINARY), rowid))
    con.commit()
    print(f"{bundle}: backgroundStyle {old} -> {args.style}  "
          f"(blob {len(blob)} -> {len(plistlib.dumps(descriptor, fmt=plistlib.FMT_BINARY))} bytes)")
    print("reboot the simulator for SpringBoard/chronod to re-read it")


if __name__ == "__main__":
    main()
