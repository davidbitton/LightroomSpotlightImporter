/* Minimal host app so Launch Services registers UTI claims + nested mdimporter.
 * Spotlight discovers importers under App.app/Contents/Library/Spotlight/.
 * A bare .mdimporter in ~/Library/Spotlight is listed by mdimport -L but
 * lsregister fails to scan it (-10811), so .lrcat stays dyn.* and never routes.
 */
#include <stdio.h>
int main(void) {
    puts("Lightroom Spotlight Importer host. The mdimporter is installed inside this app;");
    puts("Spotlight uses it automatically for .lrcat / .lrdb / .aglib catalogs.");
    return 0;
}
