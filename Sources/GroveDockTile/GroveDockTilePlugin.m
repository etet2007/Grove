#import <AppKit/AppKit.h>

// Loaded by the Dock, including while Grove is not running. Never launches Grove
// or writes to its signed bundle; preferences belong to the application domain.
@interface GroveDockTilePlugin : NSObject <NSDockTilePlugIn>
@property (strong) NSDockTile *tile;
@end

@implementation GroveDockTilePlugin
- (void)setDockTile:(NSDockTile *)tile {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    self.tile = tile;
    if (!tile) return;
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
        selector:@selector(iconChanged:) name:@"dev.stephenlau.mygit.appIconChanged"
        object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(applicationStateChanged:)
        name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [workspace addObserver:self selector:@selector(applicationStateChanged:)
        name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    [self refreshIcon];
}

- (void)iconChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshIcon]; });
}

- (void)applicationStateChanged:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    if ([app.bundleIdentifier isEqualToString:@"dev.stephenlau.mygit"]) {
        [self iconChanged:notification];
    }
}

- (void)refreshIcon {
    if (!self.tile) return;
    CFPreferencesAppSynchronize(CFSTR("dev.stephenlau.mygit"));
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("appIcon"), CFSTR("dev.stephenlau.mygit")));
    NSArray *icons = @[@"vector-green", @"glass-green", @"muted-green", @"folded-grove",
                       @"sculpted-grove", @"spring", @"summer", @"autumn", @"winter"];
    NSString *name = [value isKindOfClass:NSString.class] && [icons containsObject:value] ? value : @"vector-green";
    // AppKit owns the running app's icon. Keep custom drawing only for an
    // alternate selection after quit; the default always uses the bundle icon.
    BOOL running = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"dev.stephenlau.mygit"].count > 0;
    if (running || [name isEqualToString:@"vector-green"]) {
        self.tile.contentView = nil;
        [self.tile display];
        return;
    }
    NSURL *contents = [[[[NSBundle bundleForClass:self.class] bundleURL]
        URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
    NSBundle *resources = [NSBundle bundleWithURL:[contents URLByAppendingPathComponent:@"Resources/Grove_Grove.bundle"]];
    NSURL *url = [resources URLForResource:name withExtension:@"jp2" subdirectory:@"SystemAppIcons"];
    if (!url) url = [resources URLForResource:name withExtension:@"png" subdirectory:@"AppIcons"];
    NSImage *image = url ? [[NSImage alloc] initWithContentsOfURL:url] : nil;
    if (!image) { self.tile.contentView = nil; [self.tile display]; return; }
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, self.tile.size.width, self.tile.size.height)];
    view.image = image;
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.tile.contentView = view;
    [self.tile display];
}

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}
@end
