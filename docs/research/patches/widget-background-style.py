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

Measured on the simulator: flipping 0 -> 2 turned the plate from a flat
`(255,255,255)` / `(239,239,240)` into a blurred copy of the wallpaper —
paired regression against the wallpaper at the same coordinate, gain +0.613,
r +0.939; against a σ=4 blur of it, gain +0.670, r +0.970, r² 0.940. That is
the same cell WidgetLoft occupies on the real phone (0.612 / +0.988).

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
    parser.add_argument("style", nargs="?", type=int, default=2,
                        help="new backgroundStyle: 0 is what our widget ships with "
                             "(the flat plate), 2 is what Apple's own extensions carry "
                             "(the glass plate); 1 is untested")
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
