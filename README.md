# Lightroom Spotlight Importer

A Mac Spotlight importer (`.mdimporter`) for Adobe Lightroom Classic catalogs (`.lrcat`, `.lrdb`, `.aglib`). It lets you search, from Spotlight, for photo **filenames stored inside a catalog** without opening Lightroom.

> **Not affiliated with Adobe.** This is an unofficial third-party tool. Use it at your own risk.

## History

Code No Evil wrote LSI in 2012 for Mac OS X 10.7 (upstream: [CodeNoEvil/LightroomSpotlightImporter](https://github.com/CodeNoEvil/LightroomSpotlightImporter)). That version used the [FMDB][2] SQLite wrapper and an Xcode 4 project. The original idea still holds:

The Adobe Lightroom `.lrcat` catalog files are [SQLite](https://www.sqlite.org/) databases. A catalog does not store the pictures themselves, only references to them on disk. This query returns the filenames stored in a catalog:

	SELECT originalFilename FROM AgLibraryFile

Apple lets developers write custom Spotlight importers for lesser-known or custom file types (see the [Spotlight Importer Programming Guide][1]).

![2012 screenshot](http://www.codenoevil.com/wp-content/uploads/2012/05/Screen-Shot-2012-05-09-at-8.39.59-PM.png)

This fork ([davidbitton/LightroomSpotlightImporter](https://github.com/davidbitton/LightroomSpotlightImporter)) brings that code up to date for current macOS. See [MODERNIZATION.md](MODERNIZATION.md) for the plan and what is done.

## Status

| Item | State |
|------|-------|
| Build | Makefile + clang + macOS SDK, deployment target 11.0. **Built and tested** with Xcode 26.5 (SDK 26.5) on macOS 26.7.1 (Intel iMac). |
| Architectures | **Universal (arm64 + x86_64)** by default. The x86_64 slice has been run. The arm64 slice compiles and links but is **untested on Apple Silicon**. |
| SQLite access | Read-only. See [How it works](#how-it-works). |
| Tests | `make test` and `make matrix` pass (synthetic fixtures). The probe also passes on copies of two real Lightroom Classic catalogs (`Adobe_DBVersion` 1504001). |
| `mdimport -t` | Imports a catalog as `com.adobe.lightroom.library` and returns `com_adobe_lightroom_library_files`. Checked with an earlier x86_64 install of these sources. **Not yet** re-checked with the universal build. |
| Spotlight UI search | **Untested** in this branch. |
| Signing | Ad-hoc only. No Developer ID, Hardened Runtime or notarization. |

## Requirements

- macOS 11.0 or later (only macOS 26.7.1 has actually been tested)
- Xcode or the Command Line Tools (`clang`, macOS SDK). The Xcode GUI is not needed, and there is no `.xcodeproj`.
- Adobe **Lightroom Classic** local catalogs. Lightroom (cloud) is not supported.

## How it works

1. A tiny host app (`HostApp/`) exports the UTI `com.adobe.lightroom.library` for `lrcat`, `lrdb` and `aglib`. The importer is nested inside the app at `Contents/Library/Spotlight/`. On current macOS, `lsregister` will not register a bare `.mdimporter` (error -10811), so without the host app catalogs stay `dyn.*` and never reach the plug-in.
2. On import, the plug-in opens the catalog with the system `libsqlite3` as `file:<path>?mode=ro&immutable=1` using `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`. It then sets `PRAGMA query_only = ON` and a 2 s busy timeout. If the URI open fails, it falls back to a plain `SQLITE_OPEN_READONLY` open. With `immutable=1`, mdworker does not need write access to a WAL catalog's `-shm` file. The catalog is never written to.
3. It reads `AgLibraryFile.originalFilename`, or `baseName` + `extension` as a fallback, capped at 100,000 rows.
4. It publishes the filenames as the multivalued attribute `com_adobe_lightroom_library_files`. It also fills `kMDItemKeywords`, `kMDItemComment`, a capped `kMDItemTextContent`, and `kMDItemKind`.

Because the catalog is opened `immutable`, changes still sitting in an uncheckpointed WAL file may not be seen until Lightroom checkpoints them.

## Build

```bash
make                    # universal .mdimporter + host app, ad-hoc signed, in build/
make ARCHS=x86_64       # single-architecture build (or ARCHS=arm64)
make test               # synthetic fixture + lsi-probe + factory-symbol check
make matrix             # LRC-shaped fixture matrix (see COMPATIBILITY.md)
make clean
```

Check the result:

```bash
lipo -info build/LightroomSpotlightImporter.mdimporter/Contents/MacOS/LightroomSpotlightImporter
# Architectures in the fat file: ... are: x86_64 arm64
```

## Install

> `scripts/install.sh` was **not run** while preparing this branch. These steps describe what it does.

```bash
make install
```

This does the following:

1. It copies `Lightroom Spotlight Importer.app` to `~/Applications` and registers it with `lsregister -f`, so the UTI is known.
2. It copies `LightroomSpotlightImporter.mdimporter` to `~/Library/Spotlight/` and asks Spotlight to re-import with `mdimport -r`.

Manual equivalent:

```bash
cp -R "build/Lightroom Spotlight Importer.app" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \
  ~/Applications/"Lightroom Spotlight Importer.app"
mkdir -p ~/Library/Spotlight
cp -R build/LightroomSpotlightImporter.mdimporter ~/Library/Spotlight/
mdimport -r ~/Library/Spotlight/LightroomSpotlightImporter.mdimporter
```

If your catalogs live in a protected location (Desktop, Documents, external volumes) and imports come back empty, Spotlight may need Full Disk Access. This is **untested**.

## Verify

Work on a **copy** of a catalog. Do not point tests at a catalog Lightroom is using.

```bash
# 1. Offline, with no Spotlight involved: run the importer code against a catalog
make probe
./build/lsi-probe /tmp/Copy.lrcat 20

# 2. Is the plug-in known to Spotlight?
mdimport -L 2>&1 | grep LightroomSpotlightImporter

# 3. Test-import (does not write to the Spotlight index)
mdimport -t -d2 /tmp/Copy.lrcat
# expect: Imported '/private/tmp/Copy.lrcat' of type 'com.adobe.lightroom.library'
#         with plugIn .../LightroomSpotlightImporter.mdimporter
#         and "com_adobe_lightroom_library_files" = ( "IMG_....JPG", ... )

# 4. After indexing, read the attribute back and search
mdls -name com_adobe_lightroom_library_files /path/to/Catalog.lrcat
mdfind 'com_adobe_lightroom_library_files == "IMG_0001.JPG"'
```

Optional integration gates: `LSI_TEST_MDIMPORT=1 make test` (needs an installed importer) and `LSI_TEST_CATALOG=/tmp/Copy.lrcat make test`.

## Package

```bash
make package
# dist/LightroomSpotlightImporter-<version>-<archs>.zip
# dist/LightroomSpotlightImporter-<version>-<archs>.pkg   (host app -> /Applications)
```

Packaging was **not re-run** with the universal build.

## Project layout

| Path | Role |
|------|------|
| `LightroomSpotlightImporter/` | Importer sources (`main.c` CFPlugin glue, `GetMetadataForFile.m`, `LSIImporter.m`), schema, Info.plist |
| `HostApp/` | Minimal LSUIElement host app (UTI export plus the nested importer) |
| `Makefile` | Build system |
| `tools/lsi-probe.m` | CLI that runs the importer body against a catalog |
| `scripts/` | install, package, test, matrix |
| `tests/` | Synthetic fixture generators |
| `MODERNIZATION.md` | Plan and checklist |
| `COMPATIBILITY.md` | Lightroom Classic catalog compatibility notes |

## Technical notes

- The project has no FMDB or Omni frameworks and links only the system `libsqlite3`.
- `MetadataImporterPluginFactory` is marked default-visibility. Under `-fvisibility=hidden` it would otherwise be hidden, and `mdimport` would report "no plugIn".

## License

Apache License 2.0. Copyright (c) 2012 Code No Evil LLC.

Adobe, Lightroom, and related marks are trademarks of Adobe. This project is independent and unofficial.

[1]: https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/MDImporters/MDImporters.html "Spotlight Importer Programming Guide"
[2]: https://github.com/ccgus/fmdb "FMDB"
