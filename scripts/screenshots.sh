#!/bin/zsh
# Regenerates the README screenshots from the demo data (English, light and dark mode) into
# .github/screenshots/. Requires ImageMagick (`brew install imagemagick`).
#
#   scripts/screenshots.sh mac               builds unbox and captures the macOS popover
#   scripts/screenshots.sh windows <folder>  frames the PNGs saved on Windows by
#                                            unbox.exe --demo --snapshot <folder> [--theme dark]
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="$ROOT/.github/screenshots"
mkdir -p "$OUT"

case "${1:-}" in
  mac)
    "$ROOT/scripts/build.sh" >/dev/null
    # A copy with its own bundle identifier keeps the demo's settings away from the real app.
    DEMO="$ROOT/build/unbox-demo.app"
    DOMAIN=com.emiterkamieni.unbox.demo
    rm -rf "$DEMO"
    ditto "$ROOT/build/unbox.app" "$DEMO"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOMAIN" "$DEMO/Contents/Info.plist"
    codesign --force --sign - "$DEMO"
    defaults delete "$DOMAIN" >/dev/null 2>&1 || true
    for appearance in light dark; do
      "$DEMO/Contents/MacOS/unbox" --demo --appearance "$appearance" --snapshot "$OUT" -language en
    done
    defaults delete "$DOMAIN" >/dev/null 2>&1 || true
    rm -rf "$DEMO"
    ;;

  windows)
    SOURCE="${2:?folder with windows-*.png from unbox.exe --snapshot}"
    for file in "$SOURCE"/windows-*.png; do
      name="${file:t}"
      if [[ "$name" == *-dark.png ]]; then border='rgba(255,255,255,0.10)'; else border='rgba(0,0,0,0.12)'; fi
      read -r width height <<< "$(magick identify -format '%w %h' "$file")"
      # Windows 11 flyout frame: 8 px corners and a hairline border (the renders are 2x), plus a soft
      # shadow, with the same 40 pt margin as the macOS screenshots.
      magick -size "$((width + 160))x$((height + 160))" xc:none \
        \( "$file" \
           \( -size "${width}x${height}" xc:none -fill white -draw "roundrectangle 0,0 $((width - 1)),$((height - 1)) 16,16" \) \
           -alpha set -compose DstIn -composite -compose Over \
           -fill none -stroke "$border" -strokewidth 2 -draw "roundrectangle 1,1 $((width - 2)),$((height - 2)) 15,15" \
           -repage +80+80 \) \
        \( +clone -background 'rgba(0,0,0,0.26)' -shadow 100x26+0+12 \) -swap 1,2 \
        -background none -layers flatten -strip "$OUT/$name"
      echo "$OUT/$name"
    done
    ;;

  *)
    sed -n '2,8p' "$0"
    exit 1
    ;;
esac
