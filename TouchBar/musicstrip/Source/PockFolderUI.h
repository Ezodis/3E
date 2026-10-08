// Adapted from Pock/PockV2's MIT-licensed DockFolderController,
// DockFolderRepository and DockFolderItemView. See Resources/Pock-LICENSE.txt.
// The original compiled interface is retained; routing uses MusicStrip's panel.
@interface PockFolderItemView : NSScrubberItemView
@property NSImageView *iconView;
@property NSTextField *nameLabel;
@property NSTextField *detailLabel;
- (void)setEntry:(NSDictionary *)entry;
@end
@implementation PockFolderItemView
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:NSMakeRect(0,0,40,30)])) {
        self.wantsLayer=YES; self.layer.cornerRadius=6;
        self.iconView=[[NSImageView alloc] initWithFrame:NSMakeRect(2,3,24,24)];
        self.iconView.imageScaling=NSImageScaleProportionallyDown;
        self.nameLabel=[NSTextField labelWithString:@""];
        self.detailLabel=[NSTextField labelWithString:@""];
        self.nameLabel.font=[NSFont systemFontOfSize:9];
        self.detailLabel.font=[NSFont systemFontOfSize:9];
        self.detailLabel.textColor=[NSColor colorWithRed:124./255 green:131./255 blue:127./255 alpha:1];
        self.nameLabel.lineBreakMode=NSLineBreakByTruncatingTail;
        self.detailLabel.lineBreakMode=NSLineBreakByTruncatingTail;
        [self addSubview:self.iconView]; [self addSubview:self.nameLabel]; [self addSubview:self.detailLabel];
    }
    return self;
}
- (void)layout {
    [super layout];
    self.iconView.frame=NSMakeRect(2,3,24,24);
    self.nameLabel.frame=NSMakeRect(32,15,MAX(1,NSWidth(self.bounds)-34),12);
    self.detailLabel.frame=NSMakeRect(32,2,MAX(1,NSWidth(self.bounds)-34),12);
}
- (void)setEntry:(NSDictionary *)entry {
    self.iconView.image=entry[@"icon"]; self.nameLabel.stringValue=entry[@"name"] ?: @"";
    self.detailLabel.stringValue=entry[@"detail"] ?: @"";
    [self setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@",self.nameLabel.stringValue,self.detailLabel.stringValue]];
}
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.layer.backgroundColor=(highlighted ? NSColor.darkGrayColor : NSColor.clearColor).CGColor; }
- (void)prepareForReuse { [super prepareForReuse]; [self setEntry:@{}]; }
@end

static NSImage *PockFilePreview(NSURL *url) {
    static void *framework; static void *(*Create)(CFAllocatorRef,CFURLRef,CGSize,CFDictionaryRef); static CGImageRef (*CopyImage)(void *);
    static dispatch_once_t once;
    dispatch_once(&once,^{
        framework=dlopen("/System/Library/Frameworks/QuickLook.framework/QuickLook",RTLD_LAZY);
        Create=dlsym(framework ?: RTLD_DEFAULT,"QLThumbnailCreate"); CopyImage=dlsym(framework ?: RTLD_DEFAULT,"QLThumbnailCopyImage");
    });
    if(Create && CopyImage) {
        void *thumbnail=Create(kCFAllocatorDefault,(__bridge CFURLRef)url,CGSizeMake(30,30),NULL);
        CGImageRef image=thumbnail ? CopyImage(thumbnail) : NULL;
        NSImage *result=image ? [[NSImage alloc] initWithCGImage:image size:NSMakeSize(30,30)] : nil;
        if(image) CGImageRelease(image); if(thumbnail) CFRelease(thumbnail);
        if(result) return result;
    }
    return [NSWorkspace.sharedWorkspace iconForFile:url.path];
}

@interface PockFolderBrowser : NSObject <NSScrubberDataSource,NSScrubberDelegate,NSScrubberFlowLayoutDelegate>
@property NSTextField *folderName;
@property NSTextField *folderDetail;
@property NSScrubber *scrubber;
@property NSTouchBar *touchBar;
@property NSArray *nibObjects;
@property NSArray<NSDictionary *> *entries;
@property NSURL *url;
@property (copy) void (^onClose)(void);
@property (copy) void (^onBack)(void);
@property (copy) void (^onNavigate)(NSURL *);
@property BOOL ready;
- (BOOL)loadFolder:(NSURL *)url nested:(BOOL)nested;
@end
@implementation PockFolderBrowser
- (BOOL)loadFolder:(NSURL *)url nested:(BOOL)nested {
    NSImage *close=[[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"CloseButton" ofType:@"png"]];
    [close setName:@"CloseButton"];
    NSNib *nib=[[NSNib alloc] initWithNibNamed:@"PockFolderController" bundle:NSBundle.mainBundle];
    NSArray *objects=nil;
    if(![nib instantiateWithOwner:self topLevelObjects:&objects] || !self.touchBar || !self.scrubber) { NSLog(@"Could not load original Pock folder interface"); return NO; }
    self.nibObjects=objects; self.url=url; self.entries=@[];
    [self.scrubber registerClass:PockFolderItemView.class forItemIdentifier:@"PockFolderItem"];
    self.scrubber.dataSource=self; self.scrubber.delegate=self;
    self.scrubber.mode=NSScrubberModeFree; self.scrubber.continuous=NO;
    self.folderName.stringValue=[url.lastPathComponent isEqualToString:@".Trash"] ? @"Trash" : url.lastPathComponent;
    self.folderDetail.stringValue=@"Loading…";
    NSMutableArray *ids=[self.touchBar.defaultItemIdentifiers mutableCopy];
    NSString *closeID=nil;
    for(NSString *identifier in [ids copy]) {
        NSTouchBarItem *item=[self.touchBar itemForIdentifier:identifier];
        NSView *view=[item isKindOfClass:NSCustomTouchBarItem.class] ? ((NSCustomTouchBarItem *)item).view : nil;
        if([view isKindOfClass:NSButton.class] && ((NSButton *)view).action==@selector(willClose:)) { closeID=identifier; ((NSButton *)view).image=close; }
    }
    if(!nested) [ids removeObject:@"BackButton"];
    if(closeID) { [ids removeObject:closeID]; [ids addObject:closeID]; }
    self.touchBar.defaultItemIdentifiers=ids;
    __weak PockFolderBrowser *weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSArray *keys=@[NSURLNameKey,NSURLLocalizedTypeDescriptionKey,NSURLIsDirectoryKey,NSURLIsApplicationKey];
        NSDirectoryEnumerator *enumerator=[NSFileManager.defaultManager enumeratorAtURL:url includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsSubdirectoryDescendants|NSDirectoryEnumerationSkipsPackageDescendants|NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        NSMutableArray *entries=[NSMutableArray array];
        for(NSURL *file in enumerator) {
            NSDictionary *values=[file resourceValuesForKeys:keys error:nil];
            if(!values) continue;
            NSString *name=values[NSURLNameKey] ?: file.lastPathComponent;
            if([name hasSuffix:@".app"]) name=[name stringByDeletingPathExtension];
            NSImage *image=PockFilePreview(file);
            [entries addObject:@{@"url":file,@"name":name,@"detail":values[NSURLLocalizedTypeDescriptionKey] ?: @"",@"directory":values[NSURLIsDirectoryKey] ?: @NO,@"application":values[NSURLIsApplicationKey] ?: @NO,@"icon":image ?: [NSImage new]}];
        }
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ return [a[@"name"] compare:b[@"name"]]; }];
        dispatch_async(dispatch_get_main_queue(),^{
            PockFolderBrowser *browser=weakSelf; if(!browser) return;
            browser.entries=entries; browser.ready=YES; browser.folderDetail.stringValue=[NSString stringWithFormat:@"%lu elements",(unsigned long)entries.count];
            [browser.scrubber reloadData];
        });
    });
    return YES;
}
- (NSInteger)numberOfItemsForScrubber:(NSScrubber *)scrubber { return self.entries.count; }
- (NSScrubberItemView *)scrubber:(NSScrubber *)scrubber viewForItemAtIndex:(NSInteger)index {
    PockFolderItemView *view=(id)[scrubber makeItemWithIdentifier:@"PockFolderItem" owner:self]; [view setEntry:self.entries[index]]; return view;
}
- (NSSize)scrubber:(NSScrubber *)scrubber layout:(NSScrubberFlowLayout *)layout sizeForItemAtIndex:(NSInteger)index {
    NSDictionary *item=self.entries[index]; NSDictionary *attributes=@{NSFontAttributeName:[NSFont systemFontOfSize:10]};
    NSString *name=item[@"name"], *detail=item[@"detail"];
    if(name.length>20) name=[[name substringToIndex:17] stringByAppendingString:@"…"];
    if(detail.length>20) detail=[[detail substringToIndex:17] stringByAppendingString:@"…"];
    return NSMakeSize(MAX(30,32+MAX([name sizeWithAttributes:attributes].width,[detail sizeWithAttributes:attributes].width)),30);
}
- (void)scrubber:(NSScrubber *)scrubber didSelectItemAtIndex:(NSInteger)index {
    if(index<0 || index>=(NSInteger)self.entries.count) return;
    NSDictionary *entry=self.entries[index]; scrubber.selectedIndex=-1;
    if([entry[@"directory"] boolValue] && ![entry[@"application"] boolValue]) { if(self.onNavigate) self.onNavigate(entry[@"url"]); }
    else { [NSWorkspace.sharedWorkspace openURL:entry[@"url"]]; if(self.onClose) self.onClose(); }
}
- (void)willClose:(id)sender { if(self.onClose) self.onClose(); }
- (void)willDismiss:(id)sender { if(self.onBack) self.onBack(); }
- (void)willOpen:(id)sender { [NSWorkspace.sharedWorkspace openURL:self.url]; if(self.onClose) self.onClose(); }
@end
