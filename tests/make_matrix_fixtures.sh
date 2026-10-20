#!/usr/bin/env bash
# Synthetic LRC-shaped catalogs for the compatibility matrix.
# Lightroom Classic only — not cloud LR, not pre-Classic product claims.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/tests/fixtures/matrix}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

mk() {
  local name="$1"
  local sql="$2"
  local path="$OUT_DIR/$name"
  rm -f "$path"
  sqlite3 "$path" <<<"$sql"
  echo "  $path"
}

echo "Writing LRC matrix fixtures → $OUT_DIR"

mk "lrc-current-db1504001.lrcat" "
CREATE TABLE Adobe_variablesTable (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, type, value NOT NULL DEFAULT ''
);
INSERT INTO Adobe_variablesTable (id_global, name, value) VALUES
  ('v1', 'Adobe_DBVersion', '1504001'),
  ('v2', 'Adobe_CrsVersion', '18.0.0');
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '',
  folder INTEGER NOT NULL DEFAULT 0,
  originalFilename NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension, originalFilename) VALUES
  ('g1', 'LSI_MATRIX_LRC_CURRENT_A', 'JPG', 'LSI_MATRIX_LRC_CURRENT_A.JPG'),
  ('g2', 'LSI_MATRIX_LRC_CURRENT_B', 'CR3', 'LSI_MATRIX_LRC_CURRENT_B.CR3');
"

mk "lrc-prior-db1100000.lrcat" "
CREATE TABLE Adobe_variablesTable (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, type, value NOT NULL DEFAULT ''
);
INSERT INTO Adobe_variablesTable (id_global, name, value) VALUES
  ('v1', 'Adobe_DBVersion', '1100000'),
  ('v2', 'Adobe_CrsVersion', '11.0.0');
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '',
  originalFilename NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension, originalFilename) VALUES
  ('g1', 'LSI_MATRIX_LRC_PRIOR_A', 'NEF', 'LSI_MATRIX_LRC_PRIOR_A.NEF'),
  ('g2', 'LSI_MATRIX_LRC_PRIOR_B', 'DNG', 'LSI_MATRIX_LRC_PRIOR_B.DNG');
"

mk "lrc-older-db600000.lrcat" "
CREATE TABLE Adobe_variablesTable (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, type, value NOT NULL DEFAULT ''
);
INSERT INTO Adobe_variablesTable (id_global, name, value) VALUES
  ('v1', 'Adobe_DBVersion', '600000');
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '',
  originalFilename NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension, originalFilename) VALUES
  ('g1', 'LSI_MATRIX_LRC_OLDER_A', 'CR2', 'LSI_MATRIX_LRC_OLDER_A.CR2');
"

mk "lrc-fallback-basename.lrcat" "
CREATE TABLE Adobe_variablesTable (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, type, value NOT NULL DEFAULT ''
);
INSERT INTO Adobe_variablesTable (id_global, name, value) VALUES
  ('v1', 'Adobe_DBVersion', '1504001');
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension) VALUES
  ('g1', 'LSI_MATRIX_LRC_FALLBACK_A', 'JPG'),
  ('g2', 'LSI_MATRIX_LRC_FALLBACK_B', 'TIF');
"

mk "lrc-empty.lrcat" "
CREATE TABLE Adobe_variablesTable (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, type, value NOT NULL DEFAULT ''
);
INSERT INTO Adobe_variablesTable (id_global, name, value) VALUES
  ('v1', 'Adobe_DBVersion', '1504001');
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '',
  originalFilename NOT NULL DEFAULT ''
);
"

mk "lrc-current.lrdb" "
CREATE TABLE AgLibraryFile (
  id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
  baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '',
  originalFilename NOT NULL DEFAULT ''
);
INSERT INTO AgLibraryFile (id_global, baseName, extension, originalFilename) VALUES
  ('g1', 'LSI_MATRIX_LRC_LRDB', 'JPG', 'LSI_MATRIX_LRC_LRDB.JPG');
"

mk "lrc-broken-no-table.lrcat" "
CREATE TABLE NotTheLibrary (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO NotTheLibrary (name) VALUES ('nope');
"

cat > "$OUT_DIR/manifest.tsv" << 'MAN'
# id	file	expect	min_files	token
lrc-current	lrc-current-db1504001.lrcat	ok	2	LSI_MATRIX_LRC_CURRENT_A.JPG
lrc-prior	lrc-prior-db1100000.lrcat	ok	2	LSI_MATRIX_LRC_PRIOR_A.NEF
lrc-older	lrc-older-db600000.lrcat	ok	1	LSI_MATRIX_LRC_OLDER_A.CR2
lrc-fallback	lrc-fallback-basename.lrcat	ok	2	LSI_MATRIX_LRC_FALLBACK_A.JPG
lrc-empty	lrc-empty.lrcat	ok	0	
lrc-lrdb	lrc-current.lrdb	ok	1	LSI_MATRIX_LRC_LRDB.JPG
lrc-broken	lrc-broken-no-table.lrcat	fail	0	
MAN

echo "manifest: $OUT_DIR/manifest.tsv"
