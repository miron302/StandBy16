#import <UIKit/UIKit.h>

// Watches charging / orientation / lock / screen / motion state inside SpringBoard and
// shows the StandBy overlay when: locked + charging + landscape + stationary + screen on.
@interface SBYController : NSObject
+ (instancetype)shared;
- (void)start;
// Enlarged notification banner (called from the BBServer hooks in Tweak.x).
- (void)showBannerApp:(NSString *)app title:(NSString *)title message:(NSString *)message sectionID:(NSString *)sectionID;
// Called from the CSCoverSheetViewController hook in Tweak.x.
- (void)setCoverSheetViewController:(UIViewController *)vc;
// YES while StandBy is on screen (the lock screen asks this to decide whether to show the status bar).
- (BOOL)standByActive;
@end
