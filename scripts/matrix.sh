#!/usr/bin/env bash
# LRC compatibility matrix: synthetic LRC-shaped fixtures + optional live catalogs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROBE="${ROOT}/build/lsi-probe"
MATRIX_DIR="${ROOT}/tests/fixtures/matrix"
MDIMPORT="${LSI_TEST_MDIMPORT:-0}"
FAIL=0
PASS=0

make all probe >/dev/null
"$ROOT/tests/make_matrix_fixtures.sh" "$MATRIX_DIR"

echo "========================================"
echo " LSI LRC compatibility matrix (synthetic)"
echo "========================================"
printf '%-12s %-40s %-8s %s\n' "ID" "FILE" "RESULT" "DETAIL"
printf '%-12s %-40s %-8s %s\n' "------------" "----------------------------------------" "--------" "------"

while IFS=$'\t' read -r id file expect min_files token; do
  [[ "$id" =~ ^# ]] && continue
  [[ -z "${id// }" ]] && continue
  path="$MATRIX_DIR/$file"
  if [[ ! -f "$path" ]]; then
    printf '%-12s %-40s %-8s %s\n' "$id" "$file" "FAIL" "missing fixture"
    FAIL=$((FAIL + 1))
    continue
  fi

  set +e
  out=$("$PROBE" "$path" 2>&1)
  rc=$?
  set -e

  files=$(echo "$out" | head -1 | sed -n 's/.*files=\([0-9]*\).*/\1/p')
  files=${files:-0}
  detail=""
  status="FAIL"

  if [[ "$expect" == "fail" ]]; then
    if [[ $rc -ne 0 ]]; then
      status="PASS"
      detail="probe failed as expected (rc=$rc)"
    else
      detail="expected fail, got ok files=$files"
    fi
  else
    if [[ $rc -ne 0 ]]; then
      detail="probe rc=$rc: $(echo "$out" | head -1)"
    elif [[ "$files" -lt "$min_files" ]]; then
      detail="files=$files < min $min_files"
    elif [[ -n "$token" ]] && ! echo "$out" | grep -qF "$token"; then
      detail="missing token $token"
    else
      status="PASS"
      detail="files=$files"
      # optional Adobe_DBVersion stamp
      dbv=$(sqlite3 "$path" "SELECT value FROM Adobe_variablesTable WHERE name='Adobe_DBVersion' LIMIT 1;" 2>/dev/null || true)
      [[ -n "$dbv" ]] && detail="$detail db=$dbv"
    fi
  fi

  if [[ "$status" == "PASS" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
  printf '%-12s %-40s %-8s %s\n' "$id" "$file" "$status" "$detail"

  if [[ "$MDIMPORT" == "1" && "$expect" == "ok" && "$min_files" -gt 0 ]]; then
    set +e
    mout=$(mdimport -d2 -t "$path" 2>&1)
    set -e
    if echo "$mout" | grep -q 'with plugIn' && echo "$mout" | grep -q 'com_adobe_lightroom_library_files'; then
      echo "             mdimport                                 PASS     custom attrs present"
      PASS=$((PASS + 1))
    else
      echo "             mdimport                                 FAIL     install host? make install"
      FAIL=$((FAIL + 1))
    fi
  fi
done < "$MATRIX_DIR/manifest.tsv"

echo
echo "========================================"
echo " Live LRC catalogs (optional)"
echo "========================================"
# LSI_TEST_CATALOG (single) or LSI_TEST_CATALOGS (newline/colon separated)
live_list=()
if [[ -n "${LSI_TEST_CATALOG:-}" ]]; then
  live_list+=("$LSI_TEST_CATALOG")
fi
if [[ -n "${LSI_TEST_CATALOGS:-}" ]]; then
  # allow newline or colon separators
  while IFS= read -r line; do
    [[ -n "$line" ]] && live_list+=("$line")
  done < <(echo "$LSI_TEST_CATALOGS" | tr ':' '\n')
fi

if [[ ${#live_list[@]} -eq 0 ]]; then
  echo "(none — set LSI_TEST_CATALOG or LSI_TEST_CATALOGS)"
else
  printf '%-12s %-50s %-8s %s\n' "LIVE" "PATH" "RESULT" "DETAIL"
  for path in "${live_list[@]}"; do
    [[ -f "$path" ]] || { printf '%-12s %-50s %-8s %s\n' "live" "$(basename "$path")" "SKIP" "not found"; continue; }
    dbv=$(sqlite3 "$path" "SELECT value FROM Adobe_variablesTable WHERE name='Adobe_DBVersion' LIMIT 1;" 2>/dev/null || echo "?")
    crs=$(sqlite3 "$path" "SELECT value FROM Adobe_variablesTable WHERE name='Adobe_CrsVersion' LIMIT 1;" 2>/dev/null || echo "?")
    set +e
    out=$("$PROBE" "$path" 20 2>&1)
    rc=$?
    set -e
    files=$(echo "$out" | head -1 | sed -n 's/.*files=\([0-9]*\).*/\1/p')
    files=${files:-0}
    if [[ $rc -eq 0 && "$files" -gt 0 ]]; then
      printf '%-12s %-50s %-8s %s\n' "live" "$(basename "$path")" "PASS" "files=$files Adobe_DBVersion=$dbv CRS=$crs"
      PASS=$((PASS + 1))
    elif [[ $rc -eq 0 ]]; then
      printf '%-12s %-50s %-8s %s\n' "live" "$(basename "$path")" "PASS" "files=0 (empty?) DB=$dbv"
      PASS=$((PASS + 1))
    else
      printf '%-12s %-50s %-8s %s\n' "live" "$(basename "$path")" "FAIL" "$(echo "$out" | head -1)"
      FAIL=$((FAIL + 1))
    fi
  done
fi

echo
echo "========================================"
echo " Coverage claim (honest)"
echo "========================================"
cat << 'CLAIM'
Scope: Adobe Lightroom Classic (LRC) only.

Synthetic matrix covers LRC query shapes:
  • AgLibraryFile + originalFilename (current / prior / older DB stamps)
  • basename+extension fallback
  • empty library, .lrdb extension, missing-table failure

Not supported / not claimed:
  • Lightroom cloud
  • Pre-Classic LR desktop as a product target
  • Every Adobe_DBVersion ever shipped without a live LRC sample

Live LRC catalogs prove real Adobe_DBVersion stamps when LSI_TEST_CATALOG(S) set.
CLAIM

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
echo "Matrix OK."
