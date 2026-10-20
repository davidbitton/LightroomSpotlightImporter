# LRC catalog compatibility

**Supported product: Adobe Lightroom Classic (LRC) only** — local SQLite catalogs (`.lrcat` / `.lrdb` / `.aglib`).

Out of scope (do not claim):

- Lightroom cloud (mobile/web “Lightroom”)
- Pre-Classic Lightroom desktop (LR 1–6) as a support target
- `.lrcat-data` packages, previews, smart previews

## What we query (LRC)

1. **Primary:** `SELECT originalFilename FROM AgLibraryFile …`
2. **Fallback:** `baseName` + `extension` if `originalFilename` is missing/unusable

Open path: read-only, WAL-safe (`file:…?mode=ro&immutable=1`) for mdworker. A plain `SQLITE_OPEN_READONLY` open is the fallback.

## Version marker (LRC)

LRC catalogs often store:

| Key | Table | Example |
|-----|--------|-------------------------|
| `Adobe_DBVersion` | `Adobe_variablesTable` | `1504001` |
| `Adobe_CrsVersion` | `Adobe_variablesTable` | `18.0.0` |

`Adobe_DBVersion` is Adobe’s internal catalog schema stamp, **not** the marketing year (“Classic 2025”). LSI does not branch on it; it needs a stable LRC `AgLibraryFile` shape.

## Matrix (LRC)

```bash
make matrix                          # synthetic LRC-shaped fixtures
LSI_TEST_CATALOG=/tmp/CatalogCopy.lrcat make matrix
LSI_TEST_MDIMPORT=1 make matrix      # Spotlight path (needs make install)
```

### Synthetic fixtures

All fixtures are **LRC-shaped** SQLite stubs (not full Adobe catalogs). They exercise query paths LSI uses against Classic libraries.

| ID | Intent | Expect |
|----|--------|--------|
| `lrc-current` | `Adobe_DBVersion=1504001` + `originalFilename` | ok |
| `lrc-prior` | Older LRC stamp `1100000`, still `originalFilename` | ok |
| `lrc-older` | Older LRC stamp `600000`, still `originalFilename` | ok |
| `lrc-fallback` | No `originalFilename` → basename path | ok |
| `lrc-empty` | Valid table, 0 rows | ok |
| `lrc-lrdb` | `.lrdb` extension | ok |
| `lrc-broken` | No `AgLibraryFile` | fail cleanly |

### Live LRC catalogs

Verified 2026-10-20 against **copies** of the author's local catalogs in `/tmp`, using the universal `lsi-probe` (x86_64 slice, Intel Mac, macOS 26.7.1). The SHA-256 of each copy was unchanged after the probe ran, and no `-wal`/`-shm` files were created.

| Catalog | `Adobe_DBVersion` | `Adobe_CrsVersion` | `AgLibraryFile` rows | Status |
|---------|-------------------|--------------------|----------------------|--------|
| Main Lightroom Classic catalog | 1504001 | 18.0.0 | 3,869 (all with `originalFilename`) | PASS (probe; `mdimport -t` with the earlier x86_64 install) |
| Second Lightroom Classic catalog | 1504001 | 18.0.0 | 3,869 (all with `originalFilename`) | PASS (probe) |

```bash
LSI_TEST_CATALOGS="/tmp/catalog1.lrcat:/tmp/catalog2.lrcat" make matrix
```

## Product scope

| Product | Status |
|---------|--------|
| **Lightroom Classic (LRC)** local `.lrcat` / `.lrdb` / `.aglib` | **Supported** |
| Lightroom cloud | **Not supported** |
| Pre-Classic LR desktop | **Not a support target** |
| Preview / helper packages | **Not indexed** |

## Adding another live LRC catalog

1. Copy the `.lrcat` (preferred) or quit LRC.
2. Record stamps:

   ```bash
   sqlite3 catalog.lrcat \
     "SELECT name, value FROM Adobe_variablesTable
      WHERE name IN ('Adobe_DBVersion','Adobe_CrsVersion');"
   ```

3. `LSI_TEST_CATALOG=/path/to/catalog.lrcat make matrix`
4. Append a row to the live table above.
