#import <UIKit/UIKit.h>

// Watches charging / orientation / lock / screen / motion state inside SpringBoard and
// shows the StandBy overlay when: locked + charging + landscape + stationary + screen on.
@interface SBYController : NSObject
+ (instancetype)shared;
- (void)start;
// Enlarged notification banner (called from the BBServer hooks in Tweak.x).
- (void)showBannerApp:(NSString *)app title:(NSString *)title message:(NSString *)message sectionID:(NSString *)sectionID;
@end
