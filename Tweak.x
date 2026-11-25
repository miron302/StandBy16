// StandBy16 - iOS 17 StandBy for iOS 16 (SpringBoard tweak)
#import <UIKit/UIKit.h>
#import "SBYController.h"
#import "SBYTheme.h"

@interface BBBulletin : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *sectionID;
@end
@interface BBServer : NSObject @end
@interface CSCoverSheetViewController : UIViewController @end

static void SBYForward(BBBulletin *b) {
    if (![b respondsToSelector:@selector(title)]) return;
    NSString *sid = b.sectionID, *title = b.title, *msg = b.message;
    NSString *app = nil;
    @try { app = [b valueForKey:@"sectionDisplayName"]; } @catch (__unused NSException *e) {}
    if (![app isKindOfClass:[NSString class]] || !app.length) app = [sid componentsSeparatedByString:@"."].lastObject;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SBYController shared] showBannerApp:app title:title message:msg sectionID:sid];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SBYController shared] start];
    });
}
%end

// The lock screen itself. StandBy lives *inside* its view, so it is always above the lock screen
// and automatically disappears when the phone unlocks (no separate window needed).
%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    [[SBYController shared] setCoverSheetViewController:self];
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[SBYController shared] setCoverSheetViewController:self];
}
// Ask iOS itself to hide the status bar while StandBy is up.
- (BOOL)prefersStatusBarHidden {
    return [[SBYController shared] standByActive] ? YES : %orig;
}
%end

// Incoming notifications: StandBy shows them enlarged. The method name differs between iOS builds, so hook both.
%hook BBServer
- (void)publishBulletin:(BBBulletin *)bulletin destinations:(unsigned long long)dest {
    %orig;
    SBYForward(bulletin);
}
- (void)publishBulletinRequest:(BBBulletin *)bulletin destinations:(unsigned long long)dest {
    %orig;
    SBYForward(bulletin);
}
%end

// Proof the dylib was injected, plus a redundant start in case applicationDidFinishLaunching: was missed
// (SBYController -start is idempotent).
%ctor {
    %init;
    SBYLogf(@"dylib loaded in %@", [NSProcessInfo processInfo].processName);
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[SBYController shared] start];
        });
    });
}
