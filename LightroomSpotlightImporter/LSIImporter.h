//
//  LSIImporter.h
//  LightroomSpotlightImporter
//
//  Copyright (c) 2012 Code No Evil LLC
//  Licensed under the Apache License, Version 2.0
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Max filenames published into Spotlight attributes (guards huge catalogs).
FOUNDATION_EXPORT const NSUInteger LSIImporterDefaultMaxFiles;

/// Custom Spotlight attribute (see schema.xml).
FOUNDATION_EXPORT NSString * const LSIAttributeLibraryFiles;

@interface LSIImporter : NSObject

/// Opens the Lightroom catalog read-only and fills Spotlight attributes.
/// Returns YES if at least the query path succeeded (zero files is still success).
- (BOOL)importFileAtPath:(NSString *)filePath
              attributes:(NSMutableDictionary *)attributes
                   error:(NSError * _Nullable * _Nullable)error;

/// Same as above with an explicit row cap (0 = unlimited; prefer a finite default).
- (BOOL)importFileAtPath:(NSString *)filePath
              attributes:(NSMutableDictionary *)attributes
                maxFiles:(NSUInteger)maxFiles
                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
