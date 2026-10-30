// StandBy16 - iOS 17 StandBy for iOS 16 (SpringBoard tweak)
#import <UIKit/UIKit.h>
#import "SBYController.h"

@interface BBBulletin : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *sectionID;
@end
@interface BBServer : NSObject @end

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
