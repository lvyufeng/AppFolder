#!/bin/bash
#掘 WidgetLoft 到底怎么拿到玻璃。它是唯一已知拿到玻璃的第三方,所以它的
# 容器是唯一能一句话定性的证据。
#
# 判据:
#   - 数据容器里有壁纸截图/裁片  -> 截图合成,不需要系统授权,我们能照抄
#   - 数据容器里没有图,却照样透  -> 系统授权,第三方这条路是关的
#
# WidgetLoft 的 bundle id 是 com.koksoft.foldermini(见 01-widgetloft-拆解.md)。
# devicectl 的 appDataContainer 只给「我们自己的容器」——之前对 Apple 的 bundle
# 报 ContainerLookupErrorDomain error 2。WidgetLoft 是第三方,所以它和我们是同
# 一类,应该读得到;读不到就等于又一条路封死,记下来。

set -uo pipefail

DEV="${1:-00008160-000E03C611100036}"
BID="com.koksoft.foldermini"
OUT="/tmp/wl-probe"

rm -rf "$OUT"; mkdir -p "$OUT"

echo "== 0. 装在不在 =="
xcrun devicectl device info apps --device "$DEV" 2>&1 | grep -i "$BID" || {
  echo "  没找到 $BID —— 先在这台手机上从 App Store 装回 WidgetLoft"; exit 0; }

echo
echo "== 1. 拉数据容器 =="
xcrun devicectl device copy from \
  --device "$DEV" \
  --domain-type appDataContainer \
  --domain-identifier "$BID" \
  --source . \
  --destination "$OUT/data" 2>&1 | tail -5

echo
echo "== 2. 数据容器里长什么样 =="
find "$OUT/data" -maxdepth 3 2>/dev/null | head -40

echo
echo "== 3. 有没有图片文件(壁纸截图的铁证) =="
find "$OUT/data" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" \) 2>/dev/null \
  | head -40
IMG=$(find "$OUT/data" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" \) 2>/dev/null | wc -l | tr -d ' ')
echo "  图片文件数:$IMG"

echo
echo "== 4. 图片尺寸(壁纸裁片会是整屏比例的小图;图标库会是方图) =="
find "$OUT/data" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -20 | while read -r f; do
  s=$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')
  echo "  $s  $(basename "$f")"
done

echo
echo "== 5. 字符串里有没有 wallpaper / screenshot 之类的名字 =="
grep -ria -o -e "wallpaper" -e "screenshot" -e "snapshot" -e "backdrop" \
  "$OUT/data" 2>/dev/null | sed 's/:.*//' | sort -u | head -20

echo
echo "== 6. 顺手截一张,确认它的玻璃在这台设备上真的在 =="
xcrun devicectl device capture screenshot --device "$DEV" --destination "$OUT/screen.png" 2>&1 | tail -2

echo
echo "结果在 $OUT。第 3/4 步有壁纸样的图 -> 截图合成;没有 -> 系统授权。"