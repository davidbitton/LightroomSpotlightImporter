#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make clean all
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  LightroomSpotlightImporter/LightroomSpotlightImporter-Info.plist 2>/dev/null || echo "2.0.0")
mkdir -p dist
ZIP="$ROOT/dist/LightroomSpotlightImporter-${VERSION}-x86_64.zip"
(
  cd build
  zip -ry "$ZIP" \
    "Lightroom Spotlight Importer.app" \
    LightroomSpotlightImporter.mdimporter
)
echo "zip: $ZIP"

# pkg installs host app to /Applications (admin) — user install still preferred
STAGE="$ROOT/dist/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Applications"
cp -R "build/Lightroom Spotlight Importer.app" "$STAGE/Applications/"
PKG="$ROOT/dist/LightroomSpotlightImporter-${VERSION}-x86_64.pkg"
pkgbuild \
  --root "$STAGE" \
  --identifier com.codenoevil.LightroomSpotlightImporter.Host \
  --version "$VERSION" \
  --install-location / \
  "$PKG"
echo "pkg: $PKG (installs host app to /Applications)"
echo "Prefer: make install  → ~/Applications + ~/Library/Spotlight"
