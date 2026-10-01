#!/bin/bash
# Install AppFolder on the physical iPhone and measure whether the widget plate
# is glass, the way WidgetLoft's is.
#
# Why this is one shot: the plate style cannot be set from code (three plate SPIs
# tested and dead — see the memory notes, all run on a build that renders and gets
# a real chronod descriptor row). The value is chosen by the system when the
# widget is **added through the widget picker**, so the one thing that has to
# happen on the phone is: delete the widget, re-add it from the picker. Then this
# script photographs the result and measures it.
#
# The measurement is the same paired-pixel method used on the simulator: inside the
# widget plate versus the bare wallpaper at the same coordinate, because the plate
# region on one Home Screen page is bare wallpaper on another.
#
#   flat white plate  -> ~ (255, 0.2)      (what the simulator gives us: descriptor 0)
#   clear glass       -> gain ~+1.0, r~+0.99 vs the unblurred wallpaper
#   frosted glass     -> gain ~+0.6, r~+0.97 vs the wallpaper blurred by sigma 4
#   WidgetLoft        -> 0.612 / +0.988   (measured on this same phone)

set -euo pipefail

DEV="${1:-Nate's iPhone}"
APP="/tmp/af-device/Build/Products/Release-iphoneos/AppFolder.app"

if [ ! -d "$APP" ]; then
  echo "no device build at $APP — build it first:" >&2
  echo "  xcodebuild -project AppFolder.xcodeproj -scheme AppFolder -configuration Release \\" >&2
  echo "    -destination 'generic/platform=iOS' -derivedDataPath /tmp/af-device build" >&2
  exit 1
fi

echo "== device =="
xcrun devicectl list devices | grep -i "$DEV" || true

echo "== install =="
xcrun devicectl device install app --device "$DEV" "$APP"

echo
echo "== now on the phone =="
echo "  1. long-press the Home Screen, remove the AppFolder widget"
echo "  2. tap +, find AppFolder, add the 中号 widget back"
echo "     (this is the step that makes the system choose the plate style)"
echo
read -r -p "press return once the widget is back on the Home Screen... " _

echo "== screenshot =="
xcrun devicectl device capture screenshot --device "$DEV" --destination /tmp/af-phone-glass.png

echo "== measure =="
python3 - <<'PY'
from PIL import Image
import statistics
im = Image.open("/tmp/af-phone-glass.png").convert("RGB")
W, H = im.size
print(f"capture {W}x{H}")
def stats(box):
    vals = [sum(p) / 3 for p in im.crop(box).getdata()]
    return round(statistics.mean(vals), 1), round(statistics.pstdev(vals), 1)
# Widget plate sits in the top row of the first Home Screen page. These are the
# proportions the simulator measurements used; adjust if the capture differs.
def B(fx0, fy0, fx1, fy1):
    return (int(fx0 * W), int(fy0 * H), int(fx1 * W), int(fy1 * H))
print("widget plate     :", stats(B(0.10, 0.09, 0.90, 0.24)))
print("wallpaper beside :", stats(B(0.02, 0.30, 0.08, 0.45)))
print("dock (glass ref) :", stats(B(0.10, 0.88, 0.90, 0.95)))
print()
print("flat white = (255, ~0.2). Anything with standard deviation > 20 inside the")
print("plate, tracking the wallpaper, is the glass.")
PY