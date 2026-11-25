#import <UIKit/UIKit.h>
#import "SBYTheme.h"

// Base class: opaque black page, redraws itself on -tick.
@interface SBYPageView : UIView
@property (nonatomic, strong) SBYTheme *theme;
@property (nonatomic) BOOL minuteTransition; // cross-dissolve when the minute changes (default YES)
@property (nonatomic) BOOL rollsDigits;      // changing digits roll up/fade instead of dissolving
@property (nonatomic) NSInteger liveFPS;     // >0: redraw this many times a second while on screen (smooth motion)
@property (nonatomic, readonly) CFTimeInterval pageAge; // seconds since the page appeared
+ (void)setAnimationsSuspended:(BOOL)suspended;         // pause live redraws (e.g. while the screen is off)
// Draws one character of the time with the entrance pop (order>=0, staggered) and the digit-roll animation.
- (void)drawChar:(NSString *)ch index:(NSUInteger)i order:(NSInteger)order at:(CGPoint)pt font:(UIFont *)font color:(UIColor *)color;
- (void)tick;
- (CGRect)safeRect;                                   // inset for the notch / rounded corners
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b; // subclasses override
// Touch forwarding from the controller; points are in this page's own coordinates. Return YES if consumed.
- (BOOL)handleTapAt:(CGPoint)p;
- (BOOL)handleLongPressAt:(CGPoint)p;
- (BOOL)isEditing;
@end

// ---- Clock view styles (swipe up/down to change) ----
@interface SBYDigitalPageView : SBYPageView @end  // big expanded digits on a gradient
@interface SBYAnalogPageView  : SBYPageView @end  // rectangular dial, alarm + date complications
@interface SBYSolarPageView   : SBYPageView @end  // time-of-day sky gradient inside the numerals
@interface SBYFloatPageView   : SBYPageView @end  // overlapping translucent bubble digits
@interface SBYFloatColorPageView : SBYPageView @end // two-tone floating digits, battery ring, alarm
@interface SBYWorldPageView   : SBYPageView @end  // dot-matrix world map + day/night line
@interface SBYBoldPageView    : SBYPageView @end  // condensed digits + date/temp/alarm column

// ---- Widgets view: two stacks side by side, each scrolls vertically ----
// Long-press a stack to edit it (add/remove widgets). Smart Rotate picks a relevant widget when idle.
@interface SBYWidgetsPageView : SBYPageView
- (void)scrollStack:(int)side by:(int)delta;      // side 0 = left, 1 = right
@end

// ---- Full-screen takeovers, shown automatically like StandBy's Now Playing / Live Activities ----
@interface SBYNowPlayingPageView : SBYPageView @end
@interface SBYTimerPageView      : SBYPageView @end
@interface SBYAlarmPageView      : SBYPageView @end  // ringing alarm with Snooze and Stop
@interface SBYCallPageView       : SBYPageView @end  // incoming / active call with Accept, Decline, End

NSArray<Class> *SBYClockStyleClasses(void);
