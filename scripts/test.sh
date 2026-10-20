#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
make all probe
"$ROOT/tests/make_fixture.sh"
FIX="$ROOT/tests/fixtures/sample.lrcat"
echo "== probe fixture =="
"$ROOT/build/lsi-probe" "$FIX"
FILES=$("$ROOT/build/lsi-probe" "$FIX" | head -1 | sed -n 's/.*files=\([0-9]*\).*/\1/p')
if [[ "${FILES:-0}" -lt 3 ]]; then
  echo "FAIL: expected >=3 files, got ${FILES:-?}" >&2
  exit 1
fi
if ! "$ROOT/build/lsi-probe" "$FIX" | grep -q 'LSI_PROBE_UNIQUE_AAA.JPG'; then
  echo "FAIL: missing unique fixture name" >&2
  exit 1
fi
echo "fixture probe OK ($FILES files)"

# Symbol export guard
if ! nm -gU "$ROOT/build/LightroomSpotlightImporter.mdimporter/Contents/MacOS/LightroomSpotlightImporter" | grep -q MetadataImporterPluginFactory; then
  echo "FAIL: factory symbol not global" >&2
  exit 1
fi
echo "factory export OK"

# Optional live catalog
if [[ -n "${LSI_TEST_CATALOG:-}" && -f "$LSI_TEST_CATALOG" ]]; then
  echo "== probe live catalog =="
  "$ROOT/build/lsi-probe" "$LSI_TEST_CATALOG" 20
fi

# Optional mdimport integration (requires prior make install / UTI host)
if [[ "${LSI_TEST_MDIMPORT:-}" == "1" ]]; then
  echo "== mdimport integration =="
  cp "$FIX" /tmp/lsi-test.lrcat
  OUT=$(mdimport -d2 -t /tmp/lsi-test.lrcat 2>&1)
  echo "$OUT" | head -5
  if ! echo "$OUT" | grep -q 'with plugIn'; then
    echo "FAIL: mdimport did not use plug-in (is host app installed? make install)" >&2
    exit 1
  fi
  if ! echo "$OUT" | grep -q 'com_adobe_lightroom_library_files'; then
    echo "FAIL: custom attribute missing from mdimport output" >&2
    exit 1
  fi
  echo "mdimport integration OK"
fi

echo "All tests passed."
