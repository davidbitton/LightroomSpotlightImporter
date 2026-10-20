# Modernization plan: Lightroom Spotlight Importer

**Fork:** https://github.com/davidbitton/LightroomSpotlightImporter  
**Upstream:** https://github.com/CodeNoEvil/LightroomSpotlightImporter  
**Last upstream activity:** 2012-05 (a Mac OS X 10.7-era `.mdimporter`)

Goal: get the importer building and running on **current macOS**, on both Apple Silicon and Intel, in a form that stays maintainable as Lightroom Classic catalog formats change.

Checkboxes are ticked only for items that are done **and** verified in the code or in a real build. Last verified 2026-10-20 on an Intel iMac (i9-10910) running macOS 26.7.1 with Xcode 26.5 / SDK 26.5.

---

## What this project is

LSI is a **Spotlight metadata importer** (`.mdimporter`) for Adobe Lightroom catalog files (`.lrcat` and related UTIs).

1. It registers for the UTI `com.adobe.lightroom.library` (extensions `lrcat`, `lrdb`, `aglib`).
2. On import, it opens the catalog as **SQLite**, read-only.
3. It runs `SELECT originalFilename FROM AgLibraryFile`, with a `baseName` + `extension` fallback.
4. It publishes the filenames into the custom attribute `com_adobe_lightroom_library_files`.

| File | Role |
|------|------|
| `main.c` | CFPlugin / `MDImporter` glue (`MetadataImporterPluginFactory`) |
| `GetMetadataForFile.m` | `GetMetadataForFile`: checks the UTI or extension, then calls `LSIImporter` |
| `LSIImporter.m` | `sqlite3` query and attribute fill |
| `schema.xml` / `schema.strings` | Custom metadata attribute schema |
| `LightroomSpotlightImporter-Info.plist` | Document types, UTI export/import, plug-in IDs |
| `HostApp/` | Host app that exports the UTI and nests the importer |

---

## Definition of done

1. [x] Builds with the current toolchain (Xcode 26.5 SDK) for **Apple Silicon**. The universal arm64 + x86_64 binary was confirmed with `lipo -info`. *The arm64 slice has not been run on Apple Silicon.*
2. [x] Installs to `~/Library/Spotlight/LightroomSpotlightImporter.mdimporter`, together with the host app in `~/Applications`. *Verified with an earlier x86_64 install made by `scripts/install.sh`: `mdimport -L` lists it. The universal build has not been installed.*
3. [ ] After `mdimport -r`, the Spotlight UI finds a filename that exists only inside a test `.lrcat`. *Untested.*
4. [ ] Safe against large catalogs. *Read-only open, `query_only`, a 2 s busy timeout and a 100,000-row cap are in the code. Behavior on very large catalogs, and against a catalog Lightroom has open, is untested.*
5. [x] Signed for local use (ad-hoc; `codesign --verify --deep --strict` passes). Notarization would only be needed for public releases.
6. [x] Clean repo: source and build files only, with build/install/test documented in the README.

---

## Phased plan

### Phase 0: Fork hygiene

- [x] Fork to `davidbitton/LightroomSpotlightImporter`
- [x] Clone to `~/src/LightroomSpotlightImporter`
- [x] Add this plan (`MODERNIZATION.md`)
- [x] Expand `.gitignore` (`build/`, `Build/`, `DerivedData/`, `dist/`, `xcuserdata/`, `*.pkg`, `*.dmg`, `.DS_Store`, SQLite sidecars under `tests/`)
- [x] Remove the tracked `Build/` tree (including the Omni frameworks), the PackageMaker `.pmdoc` and the checked-in `.pkg`. This was done as a normal cleanup commit. History is not rewritten.
- [x] Update the README with status, macOS versions, install and verify steps, and a disclaimer (unofficial, not affiliated with Adobe)

### Phase 1: Modern build

**Decision:** use a Makefile with clang and the macOS SDK instead of rebuilding the 2012 Xcode project. It needs only Xcode or the Command Line Tools, and there is no `.xcodeproj`.

- [x] Replace the 2012 Xcode project with the Makefile (bundle with package type `BNDL`, plug-in keys preserved in Info.plist)
- [x] Port `GetMetadataForFile.m`, `main.c`, `LSIImporter.*`, `schema.*` and the Info.plist keys/UTIs
- [x] Set the deployment target to **11.0** (`minos 11.0` in `LC_BUILD_VERSION`)
- [x] Architectures **arm64 + x86_64**, the default `ARCHS`. Confirmed: `Mach-O universal binary with 2 architectures: [x86_64] [arm64]`
- [x] Build with ARC (`-fobjc-arc`)
- [x] Drop the unused CoreData/Cocoa imports
- [x] Replace FMDB with the system `sqlite3` C API (`otool -L` shows only `/usr/lib/libsqlite3.dylib` and system frameworks)
- [x] Open read-only: `file:<path>?mode=ro&immutable=1` with `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX`, falling back to `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX`. Also `PRAGMA query_only = ON`.
- [ ] Fail cleanly when Lightroom has the catalog locked. *Untested.*
- [x] **Exit (Intel):** `make` produces a universal `.mdimporter` and host app
- [ ] **Exit (Apple Silicon):** build and run on an Apple Silicon Mac. *Untested.*

### Phase 2: Lightroom Classic schema and behavior

- [x] Collect test catalogs: synthetic fixtures (`tests/`), plus **copies** of two current Lightroom Classic catalogs (`Adobe_DBVersion` 1504001, `Adobe_CrsVersion` 18.0.0)
- [x] Inspect the schema: `AgLibraryFile.originalFilename` is present and filled for every row in both catalog copies (3,869 rows each)
- [ ] Extend the metadata (folder path, capture time, rating, keywords from the catalog)
- [x] Cap the work: a 100,000-row default cap in code (`LSIImporterDefaultMaxFiles`). *Not load-tested.*
- [x] Confirm the UTI: `mdimport -t` imports a copied `.lrcat` as type `com.adobe.lightroom.library`. *Checked with the earlier x86_64 install, which relies on the host app's UTI export.*
- [x] **Exit:** `mdimport -t -d2` on a catalog copy shows `com_adobe_lightroom_library_files` populated. *Checked with the earlier installed x86_64 build of these sources. Not re-checked with the universal build.*

### Phase 3: Install, security, macOS integration

- [x] Dev install to `~/Library/Spotlight/` plus a host app in `~/Applications` (`scripts/install.sh`: `lsregister -f`, `mdimport -r`). *See Definition of done #2.*
- [ ] Optional all-users install to `/Library/Spotlight/`
- [x] Codesign for local use (ad-hoc, done by `make`)
- [ ] Developer ID + Hardened Runtime + notarization, for distribution
- [x] Document that Full Disk Access may be needed for catalogs in protected locations. *Documented only; not tested.*
- [ ] **Exit:** the Spotlight UI finds a test filename from the catalog. *Untested.*

### Phase 4: Packaging and distribution

- [x] Remove the PackageMaker `.pmdoc` and the checked-in `.pkg`
- [ ] Release path: `scripts/package.sh` (zip + `pkgbuild`) exists but was **not run** with the universal build
- [ ] GitHub Actions build on `macos-latest`
- [ ] Homebrew cask (would need signing and notarization)

### Phase 5: Nice-to-haves

- [ ] Swift rewrite of the importer body
- [ ] Preference for "index on open only" versus a full content dump
- [x] Logging via `os_log` instead of `DLog`
- [ ] Lightroom cloud or multi-catalog layouts
- [x] README explains how to verify with `lsi-probe`, `mdimport -t`, `mdls` and `mdfind`
- [ ] New README screenshots

---

## Hard-won lessons (do not regress)

1. **`-fvisibility=hidden`** hides `MetadataImporterPluginFactory` unless it is marked `__attribute__((visibility("default")))`. The symptom: `mdimport` reports "with no plugIn" even though `mdimport -L` lists the bundle. `make test` checks that the symbol is exported.
2. On current macOS, **a bare `.mdimporter` plus `lsregister -f` fails with -10811**. The UTI never sticks, so `.lrcat` files stay `dyn.*` and never reach the plug-in. The fix is the minimal host app, which exports `com.adobe.lightroom.library` and nests the importer under `Contents/Library/Spotlight/`.
3. Lightroom Classic declares legacy `CFBundleTypeExtensions` for `lrcat` but no modern UTI. The system uses a dynamic UTI until something exports a real one.
4. **WAL and mdworker:** a plain `SQLITE_OPEN_READONLY` open can fail inside Spotlight for Lightroom WAL catalogs, because mdworker cannot write the `-shm` file. Use `file:<abs>?mode=ro&immutable=1`.

---

## Risk register

| Risk | Mitigation |
|------|------------|
| Catalog schema changes | Multi-query fallback (`originalFilename`, then `baseName` + `extension`); matrix fixtures |
| Lightroom holds a write lock | Read-only/immutable open; document "quit LR or copy the catalog" |
| `immutable=1` misses recent writes still in the WAL | Accepted trade-off; Spotlight re-imports when the file changes |
| Huge catalogs slow mdimport | Row cap; caps on text, keyword and comment sizes |
| UTI claimed by Adobe only | Host app exports the UTI; check with `mdls -name kMDItemContentType` |
| mdimporters restricted further in a future OS | Watch WWDC notes; plan B is a helper app plus a Core Spotlight index |

---

## Out of scope

- Windows / Linux
- Parsing photo **binaries** (catalog DB only)
- Lightroom SDK / Quick Look previews of catalogs
- Lightroom cloud

---

## Status

| Item | State |
|------|-------|
| Personal fork | Done |
| Modern build | **Done**: Makefile, universal arm64 + x86_64, deployment target 11.0 |
| Intel (x86_64) runtime | **Verified**: probe and `make test`/`make matrix`; `mdimport -t` with the earlier x86_64 install |
| Apple Silicon (arm64) runtime | **Untested** |
| Spotlight UI search | **Untested** |
| Distribution signing / notarization | Not started |
