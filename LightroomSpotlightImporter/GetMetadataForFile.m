//
//  GetMetadataForFile.m
//  LightroomSpotlightImporter
//
//  Copyright (c) 2012 Code No Evil LLC
//  Licensed under the Apache License, Version 2.0
//

#include <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <os/log.h>

#import "LSIImporter.h"

Boolean GetMetadataForFile(void *thisInterface,
                           CFMutableDictionaryRef attributes,
                           CFStringRef contentTypeUTI,
                           CFStringRef pathToFile);

static os_log_t LSILog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.codenoevil.LightroomSpotlightImporter", "mdimport");
    });
    return log;
}

static BOOL LSIPathLooksLikeLightroomCatalog(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"lrcat"] ||
           [ext isEqualToString:@"lrdb"] ||
           [ext isEqualToString:@"aglib"];
}

Boolean GetMetadataForFile(void *thisInterface,
                           CFMutableDictionaryRef attributes,
                           CFStringRef contentTypeUTI,
                           CFStringRef pathToFile)
{
    Boolean ok = FALSE;
    @autoreleasepool {
        NSString *path = (__bridge NSString *)pathToFile;
        NSString *uti = contentTypeUTI ? (__bridge NSString *)contentTypeUTI : @"";
        NSMutableDictionary *attrs = (__bridge NSMutableDictionary *)attributes;

        BOOL claimedUTI = [uti isEqualToString:@"com.adobe.lightroom.library"];
        BOOL catalogExt = LSIPathLooksLikeLightroomCatalog(path);
        if (!claimedUTI && !catalogExt) {
            os_log_debug(LSILog(), "skip path=%{public}@ uti=%{public}@", path, uti);
            return FALSE;
        }

        NSError *error = nil;
        LSIImporter *importer = [[LSIImporter alloc] init];
        ok = [importer importFileAtPath:path attributes:attrs error:&error] ? TRUE : FALSE;
        if (!ok) {
            os_log_error(LSILog(), "import failed for %{public}@: %{public}@",
                         path, error.localizedDescription);
        } else {
            os_log_info(LSILog(), "ok path=%{public}@ uti=%{public}@", path.lastPathComponent, uti);
        }
    }
    return ok;
}
