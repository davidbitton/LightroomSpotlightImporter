# Modernization plan — Lightroom Spotlight Importer

**Fork:** https://github.com/davidbitton/LightroomSpotlightImporter  
**Upstream:** https://github.com/CodeNoEvil/LightroomSpotlightImporter  
**Last upstream activity:** 2012-05 (macOS 10.7-era `.mdimporter`)

Goal: bring the importer up so it builds and runs on **current macOS (Sequoia / Apple Silicon first)**, with a path that stays maintainable as Lightroom Classic catalog formats evolve.

---

## What this project is

A **Spotlight metadata importer** (`.mdimporter`) for Adobe Lightroom catalog files (`.lrcat` / related UTIs).

Core idea (still valid):

1. Register for UTI `com.adobe.lightroom.library` (extensions `lrcat`, `lrdb`, `aglib`).
2. On import, open the catalog as **SQLite**.
3. Run `SELECT originalFilename FROM AgLibraryFile`.
4. Publish filenames into custom attribute `com_adobe_lightroom_library_files` so Spotlight can search them.

Entry points:

| File | Role |
|------|------|
| `main.c` | CFPlugin / `MDImporter` glue (`MetadataImporterPluginFactory`) |
| `GetMetadataForFile.m` | `GetMetadataForFile` → dispatches on UTI |
| `LSIImporter.m` | FMDB query + attribute fill |
| `schema.xml` / `schema.strings` | Custom metadata attribute schema |
| `LightroomSpotlightImporter-Info.plist` | Document types, UTI export, plugin IDs |

---

## Reality check vs modern macOS

### Still viable

- **`.mdimporter` / `GetMetadataForFile`** is still the supported mechanism for **third-party Spotlight metadata importers** (unlike Quick Look **`.qlgenerator`**, which Sequoia killed).
- Lightroom Classic catalogs are still **SQLite** databases; the high-level approach remains sound.
- Install + reindex pattern (`mdimport -r …`) still exists (paths and security rules tightened).

### What is frozen in 2012

| Area | Then | Now |
|------|------|-----|
| Deployment target | **10.7** | Need **11+** or **13+**; Apple Silicon |
| Arch | x86_64 only (`ARCHS_STANDARD_64_BIT` of that era) | **arm64** required; universal optional |
| SQLite access | FMDB static lib; plain `[database open]` | Prefer **read-only** open; handle **WAL**; modern FMDB or `sqlite3` C API |
| Signing | Unsigned local plug-in | **Hardened Runtime**, codesign, Gatekeeper; notarize if distributed |
| Sandbox | Loose | Importers run in a constrained environment; test carefully |
| Packaging | PackageMaker `.pmdoc` + checked-in `.pkg` | `pkgbuild` / productbuild, or simple copy to `~/Library/Spotlight` |
| Repo hygiene | **`Build/`**, intermediates, Omni frameworks, `.pkg` in git | Strip; gitignore DerivedData/build products |
| Lightroom schema | 2012 `AgLibraryFile.originalFilename` | Verify against **current Lightroom Classic** catalogs (table/column drift, multi-volume paths) |
| Dependencies | Vendor FMDB + leftover Omni install_name_tool script | SPM/CocoaPods or vendored single-source FMDB; drop Omni entirely |

**Important distinction (from QL work):** this is **not** a Quick Look generator. Sequoia’s “third-party QL is dead” story does **not** automatically kill mdimporters — but the project still needs a full modern build/signing pass and schema validation.

---

## Target product (definition of done)

1. Builds in **current Xcode** for **Apple Silicon** (universal optional).
2. Installs to `~/Library/Spotlight/LightroomSpotlightImporter.mdimporter` (or system path with docs).
3. After `mdimport -r`, Spotlight can find a known filename that exists **only** inside a test `.lrcat`.
4. Safe against large catalogs (timeouts, memory, read-only, no write locks on open LR catalogs).
5. Signed for local use; notarized if you publish releases.
6. Clean repo: source + project only; documented build/install/test.

---

## Phased plan

### Phase 0 — Fork hygiene (done / immediate)

- [x] Fork to `davidbitton/LightroomSpotlightImporter`
- [x] Clone to `~/src/LightroomSpotlightImporter`
- [ ] Add this plan (`MODERNIZATION.md`)
- [ ] Expand `.gitignore` (DerivedData, `build/`, `*.xcuserdata`, `*.pkg`, `Build/`)
- [ ] Remove tracked build artifacts and the old PackageMaker tree from **git history going forward** (delete in a cleanup commit; optional `git filter` later)
- [ ] Update README: status, macOS versions, install, **disclaimer** (unofficial, not affiliated with Adobe)

### Phase 1 — Rebuild the Xcode project

Do **not** fight the 2012 `pbxproj` forever if it resists.

1. Create a new Xcode project: **macOS → System Extension / Metadata Importer** template if available, or **Bundle** configured as `.mdimporter` (wrapper extension `mdimporter`, package type `BNDL`, plug-in keys preserved).
2. Copy/port:
   - `GetMetadataForFile.m`, `main.c` (or regenerated plugin glue), `LSIImporter.*`, `schema.*`, Info.plist keys / UTIs
3. Settings:
   - `MACOSX_DEPLOYMENT_TARGET` ≥ **11.0** (or 13.0 if you want less legacy surface)
   - Architectures: **arm64** (+ x86_64 if you still want Intel)
   - `CLANG_ENABLE_OBJC_ARC` = YES (already)
   - Drop CoreData import if unused (`GetMetadataForFile.m` imports it needlessly today)
4. Replace FMDB:
   - Prefer **current FMDB** as a few source files, **or** plain `sqlite3` with a tiny wrapper
   - Link **sqlite3** system library (not ancient static only)
5. Open flags: `SQLITE_OPEN_READONLY` | `SQLITE_OPEN_NOMUTEX` (or equivalent FMDB API); fail cleanly if catalog is locked by Lightroom.

**Exit:** `xcodebuild` succeeds on Apple Silicon; produces `.mdimporter`.

### Phase 2 — Lightroom Classic schema & behavior

1. Collect test catalogs:
   - Small synthetic / old backup `.lrcat`
   - Current Lightroom Classic catalog **copy** (never open live while LR has exclusive lock if avoidable)
2. Inspect schema:

   ```bash
   sqlite3 catalog.lrcat ".schema AgLibraryFile"
   sqlite3 catalog.lrcat "SELECT originalFilename FROM AgLibraryFile LIMIT 5;"
   ```

3. Extend metadata if useful (optional v2):
   - `relativePath` / folder path join (so search matches folder+name)
   - capture time, rating, keywords (heavier queries — gate behind performance budget)
4. Cap work: e.g. max rows or streaming into the attribute array; avoid loading multi-million-string arrays into Spotlight without bounds.
5. Confirm UTI: `com.adobe.lightroom.library` still matches modern `.lrcat` (may need additional UTIs if Adobe registers different types).

**Exit:** unit-style CLI or `mdimport -d3 -t /path/to/test.lrcat` shows `com_adobe_lightroom_library_files` populated.

### Phase 3 — Install, security, macOS integration

1. Install location:
   - Dev: `~/Library/Spotlight/`
   - Optional: `/Library/Spotlight/` for all users
2. Register:

   ```bash
   mdimport -r ~/Library/Spotlight/LightroomSpotlightImporter.mdimporter
   mdimport -d3 -t /path/to/catalog.lrcat
   ```

3. Codesign (local):

   ```bash
   codesign --force --deep --sign - LightroomSpotlightImporter.mdimporter
   ```

   For distribution: Developer ID + **Hardened Runtime** + **notarization**.
4. Privacy / TCC: document that first import may need Full Disk Access if catalogs live in protected locations (Desktop/Documents, external volumes).
5. Hardened Runtime exceptions only if proven necessary (e.g. JIT — should **not** be needed for SQLite).

**Exit:** clean `mdimport -t` on Sequoia; Spotlight UI finds a test filename from the catalog.

### Phase 4 — Packaging & distribution

1. Remove PackageMaker `.pmdoc` and checked-in `.pkg`.
2. Add a simple release path:
   - `xcodebuild` archive / build
   - `pkgbuild` **or** zip + install script that copies to `~/Library/Spotlight` and runs `mdimport -r`
3. GitHub Actions (optional): build on `macos-latest`, upload artifact (signing secrets only if you want public notarized builds).
4. Homebrew cask only if you want install-by-brew later — must meet **signing/notarization** expectations (same lesson as modern QL casks).

### Phase 5 — Nice-to-haves (after green)

- Swift rewrite of importer body (keep C plugin entry if required)
- Preference for “index on open only” vs full content dump
- Logging via `os_log` instead of `DLog`
- Support for Lightroom cloud / multi-catalog layouts if paths differ
- README screenshots and “how to verify with `mdls` / Spotlight”

---

## Risk register

| Risk | Mitigation |
|------|------------|
| Catalog schema changed | Probe with `sqlite3`; multi-query fallbacks |
| Lightroom holds write lock | Read-only open; document “quit LR or copy catalog” |
| Huge catalogs hang mdimport | Timeouts, row limits, progressive attributes |
| Adobe ships official importer | Detect conflict; document disable/replace |
| UTI claimed by Adobe only | Register as alternate importer; test with `mdls -name kMDItemContentType` |
| mdimporter restricted further in future OS | Watch WWDC notes; plan B = small helper app + Core Spotlight index of paths (different UX) |

---

## Suggested first implementation commits (on the fork)

1. `chore: gitignore build products; drop tracked Build/ and pkg from tree`
2. `docs: modernization plan + README refresh`
3. `build: new Xcode project, arm64, deployment 11+`
4. `feat: read-only SQLite open + safer FMDB/sqlite usage`
5. `test: mdimport fixtures + script`
6. `build: codesign + install script`

---

## Out of scope (initially)

- Windows / Linux
- Parsing photo **binaries** (only catalog DB)
- Full Lightroom API / SDK
- Quick Look previews of catalogs (different subsystem)

---

## References

- Original README: SQLite + `AgLibraryFile.originalFilename`
- Apple: Spotlight Importer / Metadata Importer docs (CFPlugin `MDImporter`)
- FMDB: https://github.com/ccgus/fmdb
- Local clone: `~/src/LightroomSpotlightImporter`

---

## Status

| Item | State |
|------|--------|
| Personal fork | **Done** — `davidbitton/LightroomSpotlightImporter` |
| Local clone | **Done** — `~/src/LightroomSpotlightImporter` |
| Modern build | **Not started** |
| Sequoia validation | **Not started** |
