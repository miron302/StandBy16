#import <UIKit/UIKit.h>
#import "SBYTheme.h"

// Base class: opaque black page, redraws itself on -tick.
@interface SBYPageView : UIView
@property (nonatomic, strong) SBYTheme *theme;
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

NSArray<Class> *SBYClockStyleClasses(void);
