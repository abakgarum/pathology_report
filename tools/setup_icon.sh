#!/usr/bin/env bash
# Generate the desktop app icon from tools/icon-source.svg and install
# it across every platform's AppIcon set via flutter_launcher_icons.
#
# Steps the script performs:
#   1. Render tools/icon-source.svg to a 1024x1024 master PNG using
#      whatever conversion tool is available on this machine, in this
#      preference order: rsvg-convert > inkscape > magick (ImageMagick)
#      > qlmanage. Each is widely available; rsvg-convert from
#      `brew install librsvg` produces the cleanest output.
#   2. Drops the PNG at tools/icon-master.png (the path pubspec.yaml
#      references).
#   3. Runs `dart run flutter_launcher_icons` so the per-platform icon
#      sets (macOS Assets.xcassets/AppIcon.appiconset, Windows .ico) are
#      regenerated from the new master.
#   4. Reminds you to do `flutter clean && flutter build macos --release`
#      so the new icon ends up in the shipped .app.
#
# Usage:   ./tools/setup_icon.sh

set -euo pipefail

cd "$(dirname "$0")/.."

SRC="tools/icon-source.svg"
DST="tools/icon-master.png"

if [[ ! -f "$SRC" ]]; then
  echo "✗ Source SVG not found at $SRC" >&2
  exit 1
fi

echo "→ Rendering $SRC → $DST (1024x1024)…"

rendered=false

if command -v rsvg-convert >/dev/null 2>&1; then
  echo "  using rsvg-convert"
  rsvg-convert -w 1024 -h 1024 "$SRC" -o "$DST"
  rendered=true
elif command -v inkscape >/dev/null 2>&1; then
  echo "  using inkscape"
  inkscape --export-type=png --export-filename="$DST" \
           --export-width=1024 --export-height=1024 "$SRC"
  rendered=true
elif command -v magick >/dev/null 2>&1; then
  echo "  using ImageMagick (magick)"
  magick -background none -density 384 "$SRC" \
         -resize 1024x1024 "$DST"
  rendered=true
elif command -v convert >/dev/null 2>&1; then
  echo "  using ImageMagick (convert)"
  convert -background none -density 384 "$SRC" \
          -resize 1024x1024 "$DST"
  rendered=true
elif command -v qlmanage >/dev/null 2>&1; then
  # qlmanage is macOS built-in — quality varies depending on QuickLook
  # plugins, but it's a useful last-resort that needs zero installs.
  echo "  using qlmanage (macOS built-in)"
  TMP=$(mktemp -d)
  qlmanage -t -s 1024 -o "$TMP" "$SRC" >/dev/null 2>&1 || true
  CANDIDATE=$(find "$TMP" -name '*.png' | head -n1 || true)
  if [[ -n "$CANDIDATE" ]]; then
    cp "$CANDIDATE" "$DST"
    rendered=true
  fi
  rm -rf "$TMP"
fi

if [[ "$rendered" != "true" ]]; then
  cat <<EOF >&2

✗ No SVG-to-PNG converter found on this machine.

Easiest fix (Homebrew):
    brew install librsvg
    ./tools/setup_icon.sh

Or — manually export the master PNG:
    1. Open tools/icon-source.svg in any browser (Chrome/Safari).
    2. Take a 1024×1024 screenshot or use the browser's PDF→PNG.
    3. Save as tools/icon-master.png
    4. Run: dart run flutter_launcher_icons

EOF
  exit 1
fi

echo "✓ Master PNG written: $DST ($(du -h "$DST" | cut -f1))"

echo "→ Generating per-platform icon sets…"
dart run flutter_launcher_icons

cat <<EOF

✓ Done. Icons regenerated for macOS + Windows.

Next steps:
    flutter clean
    ./tools/build_release.sh   # rebuilds with the new icon

EOF
