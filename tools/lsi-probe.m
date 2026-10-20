// CLI probe: exercises LSIImporter against a catalog path.
// Usage: lsi-probe /path/to/catalog.lrcat

#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import "LSIImporter.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: %s <catalog.lrcat> [maxFiles]\n", argv[0]);
            return 2;
        }
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        NSUInteger maxFiles = LSIImporterDefaultMaxFiles;
        if (argc >= 3) {
            maxFiles = (NSUInteger)strtoul(argv[2], NULL, 10);
        }
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        NSError *error = nil;
        LSIImporter *imp = [[LSIImporter alloc] init];
        BOOL ok = [imp importFileAtPath:path attributes:attrs maxFiles:maxFiles error:&error];
        if (!ok) {
            fprintf(stderr, "FAIL: %s\n", error.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }
        NSArray *files = attrs[LSIAttributeLibraryFiles];
        printf("ok=1 files=%lu path=%s\n", (unsigned long)files.count, path.UTF8String);
        NSUInteger show = MIN(files.count, (NSUInteger)10);
        for (NSUInteger i = 0; i < show; i++) {
            printf("  %s\n", [files[i] UTF8String]);
        }
        if (files.count > show) {
            printf("  … (%lu more)\n", (unsigned long)(files.count - show));
        }
        return 0;
    }
}
