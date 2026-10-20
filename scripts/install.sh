#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${ROOT}/build/LightroomSpotlightImporter.mdimporter"
HOST="${ROOT}/build/Lightroom Spotlight Importer.app"
DEST_PLUGIN_DIR="${HOME}/Library/Spotlight"
DEST_PLUGIN="${DEST_PLUGIN_DIR}/LightroomSpotlightImporter.mdimporter"
DEST_APP_DIR="${HOME}/Applications"
DEST_APP="${DEST_APP_DIR}/Lightroom Spotlight Importer.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$BUNDLE" || ! -d "$HOST" ]]; then
  echo "missing build products (run: make)" >&2
  exit 1
fi

if ! nm -gU "$BUNDLE/Contents/MacOS/LightroomSpotlightImporter" 2>/dev/null | grep -q MetadataImporterPluginFactory; then
  echo "ERROR: MetadataImporterPluginFactory not exported — rebuild required." >&2
  exit 1
fi

mkdir -p "$DEST_PLUGIN_DIR" "$DEST_APP_DIR"

# 1) Host app — registers UTI (critical). Nested mdimporter for Spotlight discovery.
rm -rf "$DEST_APP"
cp -R "$HOST" "$DEST_APP"
codesign --force --deep --sign - "$DEST_APP" 2>/dev/null || true
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" || true
fi

# 2) Also copy mdimporter to ~/Library/Spotlight (mdimport -L path; plugin load).
rm -rf "$DEST_PLUGIN"
cp -R "$BUNDLE" "$DEST_PLUGIN"
codesign --force --deep --sign - "$DEST_PLUGIN" 2>/dev/null || true
mdimport -r "$DEST_PLUGIN" 2>/dev/null || true
# Nested copy path too
mdimport -r "$DEST_APP/Contents/Library/Spotlight/LightroomSpotlightImporter.mdimporter" 2>/dev/null || true

echo "Installed:"
echo "  App (UTI host): $DEST_APP"
echo "  Plug-in:        $DEST_PLUGIN"
echo
echo "Verify:"
echo "  mdimport -d3 -t /path/to/catalog.lrcat"
echo "  # expect: type 'com.adobe.lightroom.library' with plugIn ...LightroomSpotlightImporter"
echo "  mdls -name com_adobe_lightroom_library_files /path/to/catalog.lrcat"
