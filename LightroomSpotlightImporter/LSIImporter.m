//
//  LSIImporter.m
//  LightroomSpotlightImporter
//
//  Copyright (c) 2012 Code No Evil LLC
//  Licensed under the Apache License, Version 2.0
//

#import "LSIImporter.h"

#import <CoreServices/CoreServices.h>
#import <os/log.h>
#import <sqlite3.h>

NSString * const LSIAttributeLibraryFiles = @"com_adobe_lightroom_library_files";
const NSUInteger LSIImporterDefaultMaxFiles = 100000;

static os_log_t LSILog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.codenoevil.LightroomSpotlightImporter", "importer");
    });
    return log;
}

static NSErrorDomain const LSIErrorDomain = @"com.codenoevil.LightroomSpotlightImporter";

enum {
    LSIErrorOpenFailed = 1,
    LSIErrorQueryFailed = 3,
};

/// Open catalog for safe concurrent read next to Lightroom (WAL).
/// Prefer immutable URI so mdworker does not need write access to -shm.
static int LSIOpenCatalog(const char *path, sqlite3 **dbOut) {
    *dbOut = NULL;
    if (!path || !path[0]) {
        return SQLITE_MISUSE;
    }

    // Absolute path required for file: URI.
    NSString *nsPath = [NSString stringWithUTF8String:path];
    if (!nsPath.absolutePath) {
        nsPath = nsPath.stringByStandardizingPath;
    }
    NSString *escaped = [nsPath stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLPathAllowedCharacterSet]];
    // immutable=1: read snapshot without WAL shared-memory writes (critical in mdworker).
    NSString *uri = [NSString stringWithFormat:@"file:%@?mode=ro&immutable=1", escaped];

    int rc = sqlite3_open_v2(uri.UTF8String, dbOut,
                             SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX,
                             NULL);
    if (rc == SQLITE_OK) {
        return rc;
    }
    if (*dbOut) {
        sqlite3_close(*dbOut);
        *dbOut = NULL;
    }

    // Fallback: plain read-only path (works in interactive tools; may fail in mdworker + WAL).
    rc = sqlite3_open_v2(path, dbOut, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
    return rc;
}

@implementation LSIImporter

- (BOOL)importFileAtPath:(NSString *)filePath
              attributes:(NSMutableDictionary *)attributes
                   error:(NSError **)error
{
    return [self importFileAtPath:filePath
                       attributes:attributes
                         maxFiles:LSIImporterDefaultMaxFiles
                            error:error];
}

- (BOOL)importFileAtPath:(NSString *)filePath
              attributes:(NSMutableDictionary *)attributes
                maxFiles:(NSUInteger)maxFiles
                   error:(NSError **)error
{
    if (filePath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LSIErrorDomain
                                         code:LSIErrorOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty catalog path"}];
        }
        return NO;
    }

    sqlite3 *db = NULL;
    int rc = LSIOpenCatalog(filePath.fileSystemRepresentation, &db);
    if (rc != SQLITE_OK) {
        const char *msg = db ? sqlite3_errmsg(db) : sqlite3_errstr(rc);
        os_log_error(LSILog(), "open failed for %{public}@: %{public}s", filePath, msg ?: "?");
        if (error) {
            *error = [NSError errorWithDomain:LSIErrorDomain
                                         code:LSIErrorOpenFailed
                                     userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Cannot open catalog (read-only): %s", msg ?: "?"],
                NSFilePathErrorKey: filePath,
            }];
        }
        if (db) {
            sqlite3_close(db);
        }
        return NO;
    }

    sqlite3_busy_timeout(db, 2000);
    sqlite3_exec(db, "PRAGMA query_only = ON;", NULL, NULL, NULL);

    static const char *const kQueries[] = {
        "SELECT originalFilename FROM AgLibraryFile WHERE originalFilename IS NOT NULL AND originalFilename != ''",
        "SELECT baseName || CASE WHEN extension IS NULL OR extension = '' THEN '' ELSE '.' || extension END "
        "FROM AgLibraryFile WHERE baseName IS NOT NULL AND baseName != ''",
        NULL
    };

    NSMutableArray<NSString *> *files = [NSMutableArray arrayWithCapacity:1024];
    BOOL queryOK = NO;
    NSString *lastSQLError = nil;

    for (const char *const *q = kQueries; *q != NULL; q++) {
        sqlite3_stmt *stmt = NULL;
        rc = sqlite3_prepare_v2(db, *q, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            lastSQLError = [NSString stringWithUTF8String:sqlite3_errmsg(db) ?: "prepare failed"];
            continue;
        }

        queryOK = YES;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(stmt, 0);
            if (!text) {
                continue;
            }
            NSString *name = [[NSString alloc] initWithUTF8String:(const char *)text];
            if (name.length == 0) {
                continue;
            }
            [files addObject:name];
            if (maxFiles > 0 && files.count >= maxFiles) {
                os_log_info(LSILog(), "row cap %lu reached", (unsigned long)maxFiles);
                break;
            }
        }

        if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
            lastSQLError = [NSString stringWithUTF8String:sqlite3_errmsg(db) ?: "step failed"];
            queryOK = (files.count > 0);
        }

        sqlite3_finalize(stmt);
        if (files.count > 0 || queryOK) {
            break;
        }
    }

    sqlite3_close(db);

    if (!queryOK && files.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:LSIErrorDomain
                                         code:LSIErrorQueryFailed
                                     userInfo:@{
                NSLocalizedDescriptionKey: lastSQLError ?: @"No usable AgLibraryFile query",
                NSFilePathErrorKey: filePath,
            }];
        }
        return NO;
    }

    attributes[LSIAttributeLibraryFiles] = [files copy];

    if (files.count > 0) {
        // kMDItemTextContent is often stripped from the real Spotlight store for
        // third-party importers (mdimport -t shows it; mdls after -i is null).
        // Still set it for test-import / any OS that keeps it.
        // Prefer space (not only newline) so "IMG_0352.JPG" tokenizes as
        // name + extension tokens Spotlight UI can match.
        NSUInteger textCap = MIN(files.count, (NSUInteger)2000);
        NSArray *textSlice = [files subarrayWithRange:NSMakeRange(0, textCap)];
        NSMutableArray<NSString *> *textTokens =
            [NSMutableArray arrayWithCapacity:textSlice.count * 2];
        for (NSString *full in textSlice) {
            [textTokens addObject:full];
            NSString *ext = full.pathExtension;
            NSString *base = full.stringByDeletingPathExtension;
            if (ext.length > 0 && base.length > 0) {
                // "IMG_0352 JPG" — UI query "IMG_0352.JPG" often becomes tokens
                // IMG_0352 + JPG after the '.' is treated as a separator.
                [textTokens addObject:[NSString stringWithFormat:@"%@ %@", base, ext]];
            }
        }
        attributes[(NSString *)kMDItemTextContent] =
            [textTokens componentsJoinedByString:@" "];

        // Keywords: must work for both "IMG_0352" and "IMG_0352.JPG".
        // Spotlight's query parser splits on '.'; store variants accordingly.
        NSUInteger keyCap = MIN(files.count, (NSUInteger)500);
        NSMutableSet<NSString *> *keywordSet = [NSMutableSet setWithCapacity:keyCap * 5];
        [keywordSet addObject:@"Lightroom"];
        [keywordSet addObject:@"LRC"];
        for (NSUInteger i = 0; i < keyCap; i++) {
            NSString *full = files[i];
            if (full.length == 0) {
                continue;
            }
            // Exact original (with extension as stored in LRC)
            [keywordSet addObject:full];
            [keywordSet addObject:full.lowercaseString];

            NSString *base = full.stringByDeletingPathExtension;
            NSString *ext = full.pathExtension;
            if (base.length > 0) {
                [keywordSet addObject:base];
                [keywordSet addObject:base.lowercaseString];
            }
            if (ext.length > 0) {
                [keywordSet addObject:ext];
                [keywordSet addObject:ext.lowercaseString];
                [keywordSet addObject:ext.uppercaseString];
                // Space form so both tokens are keywords independently
                if (base.length > 0) {
                    [keywordSet addObject:[NSString stringWithFormat:@"%@ %@", base, ext]];
                    [keywordSet addObject:
                        [NSString stringWithFormat:@"%@ %@", base.lowercaseString, ext.lowercaseString]];
                }
            }
        }
        attributes[(NSString *)kMDItemKeywords] = keywordSet.allObjects;

        // Comment: keep full names WITH extensions (comma-separated).
        NSUInteger commentCap = MIN(files.count, (NSUInteger)40);
        NSArray *commentSlice = [files subarrayWithRange:NSMakeRange(0, commentCap)];
        attributes[(NSString *)kMDItemComment] =
            [NSString stringWithFormat:@"LRC files: %@",
             [commentSlice componentsJoinedByString:@", "]];
    }

    attributes[(NSString *)kMDItemKind] = @"Adobe Lightroom Catalog";

    os_log_info(LSILog(), "imported %lu filenames from %{public}@",
                (unsigned long)files.count, filePath.lastPathComponent);
    return YES;
}

@end
