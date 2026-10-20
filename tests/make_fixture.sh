#!/usr/bin/env bash
# Build a tiny synthetic Lightroom-like catalog for offline tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/tests/fixtures/sample.lrcat}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
sqlite3 "$OUT" <<'SQL'
CREATE TABLE AgLibraryFile (
    id_local INTEGER PRIMARY KEY,
    id_global UNIQUE NOT NULL,
    baseName NOT NULL DEFAULT '',
    extension NOT NULL DEFAULT '',
    folder INTEGER NOT NULL DEFAULT 0,
    idx_filename NOT NULL DEFAULT '',
    lc_idx_filename NOT NULL DEFAULT '',
    originalFilename NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension, originalFilename, idx_filename, lc_idx_filename) VALUES
 ('g1', 'LSI_PROBE_UNIQUE_AAA', 'JPG', 'LSI_PROBE_UNIQUE_AAA.JPG', 'LSI_PROBE_UNIQUE_AAA.JPG', 'lsi_probe_unique_aaa.jpg'),
 ('g2', 'LSI_PROBE_UNIQUE_BBB', 'CR2', 'LSI_PROBE_UNIQUE_BBB.CR2', 'LSI_PROBE_UNIQUE_BBB.CR2', 'lsi_probe_unique_bbb.cr2'),
 ('g3', 'vacation_sunset', 'NEF', 'vacation_sunset.NEF', 'vacation_sunset.NEF', 'vacation_sunset.nef');
SQL
echo "wrote $OUT"
sqlite3 "$OUT" "SELECT originalFilename FROM AgLibraryFile;"
