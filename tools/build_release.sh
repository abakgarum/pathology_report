#!/usr/bin/env bash
# Build a macOS release of pathology_report and package it for sharing.
#
# What this script does:
#   1. flutter clean + pub get   (deterministic build)
#   2. flutter build macos --release
#      (Flutter ad-hoc signs the binary so it launches on Apple Silicon —
#       no Apple Developer Program account needed.)
#   3. ditto-zip the .app bundle (preserves resource forks + signature)
#   4. Print the path + the one xattr command the recipient will run.
#
# Usage:   ./tools/build_release.sh
# Output:  build/release-share/pathology_report-<version>.zip

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "✗ flutter not found in PATH. Install Flutter first." >&2
  exit 1
fi

echo "→ Cleaning previous build artefacts…"
flutter clean >/dev/null

echo "→ Fetching dependencies…"
flutter pub get >/dev/null

echo "→ Building macOS release (universal — Intel + Apple Silicon)…"
flutter build macos --release

APP_NAME="pathology_report.app"
APP_PATH="$PWD/build/macos/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✗ Build did not produce $APP_PATH" >&2
  exit 1
fi

# Read version: line is "version: 1.0.0+1" — strip key, build metadata.
VERSION=$(awk -F': ' '/^version:/ {print $2; exit}' pubspec.yaml \
          | tr -d '[:space:]' | cut -d'+' -f1)
[[ -z "$VERSION" ]] && VERSION="dev"

OUT_DIR="$PWD/build/release-share"
ZIP_PATH="$OUT_DIR/pathology_report-$VERSION.zip"
mkdir -p "$OUT_DIR"
rm -f "$ZIP_PATH"

echo "→ Packaging $(basename "$ZIP_PATH")…"
# Use ditto, NOT zip — ditto preserves the .app's resource forks and
# code-signing metadata so the recipient doesn't see "app is damaged".
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)

cat <<EOF

✓ Done.
  Built:       $APP_PATH
  Packaged:    $ZIP_PATH ($ZIP_SIZE)

Send the zip to your friend. Tell them to run AFTER extracting:

    xattr -dr com.apple.quarantine /path/to/$APP_NAME

…then double-click the app. (The xattr step is needed because the app
is ad-hoc signed but not notarized; Apple Developer Program membership
would replace it with a proper signature for free downloads.)

Reveal in Finder:
EOF

# Convenience: open the output directory.
open "$OUT_DIR" 2>/dev/null || true
