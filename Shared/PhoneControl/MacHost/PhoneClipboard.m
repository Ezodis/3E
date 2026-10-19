// SPDX-License-Identifier: MIT
// macOS pasteboard for Phone Bar's clipboard transfer. Built into
// libThreeEPhoneNative.dylib; called from MacClipboard.cs with UTF-8 buffers.
#import <AppKit/AppKit.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

static NSString *PhoneString(const char *bytes, int length) {
    if (!bytes || length <= 0) return nil;
    return [[NSString alloc] initWithBytes:bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
}

static void *PhoneCopy(NSData *data, int *length) {
    *length = 0;
    if (!data.length || data.length > INT_MAX) return NULL;
    void *copy = malloc(data.length);
    if (!copy) return NULL;
    memcpy(copy, data.bytes, data.length);
    *length = (int)data.length;
    return copy;
}

// Text, HTML and a PNG picture share one pasteboard item; files follow as
// file URLs so Finder, Mail and Messages paste them as attachments.
int ThreeEPasteboardWrite(const char *text, int textLength, const char *html, int htmlLength,
                          const unsigned char *png, int pngLength, const char *paths, int pathsLength) {
    @autoreleasepool {
        NSMutableArray *objects = [NSMutableArray array];
        NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
        BOOL filled = NO;
        NSString *plain = PhoneString(text, textLength), *rich = PhoneString(html, htmlLength);
        if (plain) { [item setString:plain forType:NSPasteboardTypeString]; filled = YES; }
        if (rich) { [item setString:rich forType:NSPasteboardTypeHTML]; filled = YES; }
        if (png && pngLength > 0) {
            NSData *data = [NSData dataWithBytes:png length:(NSUInteger)pngLength];
            NSBitmapImageRep *image = [NSBitmapImageRep imageRepWithData:data];
            if (image) {
                [item setData:data forType:NSPasteboardTypePNG];
                // Many Mac apps (Preview, Keynote, older editors) read only TIFF.
                NSData *tiff = image.TIFFRepresentation;
                if (tiff) [item setData:tiff forType:NSPasteboardTypeTIFF];
                filled = YES;
            }
        }
        if (filled) [objects addObject:item];
        for (NSString *path in [PhoneString(paths, pathsLength) componentsSeparatedByString:@"\n"])
            if (path.length) [objects addObject:[NSURL fileURLWithPath:path]];
        if (!objects.count) return 0;
        NSPasteboard *board = NSPasteboard.generalPasteboard;
        [board clearContents];
        return [board writeObjects:objects] ? 1 : 0;
    }
}

int ThreeEPasteboardRead(char **text, int *textLength, char **html, int *htmlLength,
                         unsigned char **png, int *pngLength, char **paths, int *pathsLength) {
    @autoreleasepool {
        *text = NULL; *html = NULL; *png = NULL; *paths = NULL;
        *textLength = *htmlLength = *pngLength = *pathsLength = 0;
        NSPasteboard *board = NSPasteboard.generalPasteboard;
        NSArray<NSURL *> *urls = [board readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
        NSMutableArray<NSString *> *files = [NSMutableArray array];
        for (NSURL *url in urls) if (url.isFileURL && url.path.length) [files addObject:url.path];
        if (files.count) *paths = PhoneCopy([[files componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding], pathsLength);

        NSString *plain = [board stringForType:NSPasteboardTypeString];
        // Finder adds the file names as text and the file icon as a picture;
        // with copied files, only the files are meaningful.
        if (plain && !files.count) *text = PhoneCopy([plain dataUsingEncoding:NSUTF8StringEncoding], textLength);

        NSString *rich = [board stringForType:NSPasteboardTypeHTML];
        if (!rich && !files.count) {
            // Notes, Pages and TextEdit copy RTF: convert it so formatting survives.
            NSData *rtf = [board dataForType:NSPasteboardTypeRTF];
            if (rtf) @try {
                NSAttributedString *styled = [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:nil];
                NSData *data = styled ? [styled dataFromRange:NSMakeRange(0, styled.length)
                                           documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} error:nil] : nil;
                if (data) rich = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            } @catch (NSException *ignored) { rich = nil; }
        }
        if (rich && !files.count) *html = PhoneCopy([rich dataUsingEncoding:NSUTF8StringEncoding], htmlLength);

        if (!files.count) {
            NSData *data = [board dataForType:NSPasteboardTypePNG];
            if (!data) {
                NSData *tiff = [board dataForType:NSPasteboardTypeTIFF];
                NSBitmapImageRep *image = tiff ? [NSBitmapImageRep imageRepWithData:tiff] : nil;
                data = image ? [image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
            }
            if (data) *png = PhoneCopy(data, pngLength);
        }
        return 1;
    }
}

void ThreeEPasteboardFree(void *memory) { free(memory); }
