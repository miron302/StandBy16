#import <UIKit/UIKit.h>

#define SBY_DOMAIN @"com.miron302.standby16"

// Settings live in /var/mobile/Library/Preferences/com.miron302.standby16.plist
@interface SBYPrefs : NSObject
+ (NSUserDefaults *)defaults;
+ (BOOL)enabled;
+ (BOOL)requireCharging;
+ (BOOL)keepAwake;            // NO = behave like StandBy on non-Always-On iPhones (screen sleeps, tap to wake)
+ (NSInteger)nightMode;       // 0 ambient estimate, 1 always red, 2 never red, 3 by hours
+ (NSInteger)nightStartHour;
+ (NSInteger)nightEndHour;
+ (CGFloat)nightBrightness;   // 0 = leave brightness alone
+ (CGFloat)ambientThreshold;  // system brightness below this = "dark room"
+ (double)latitude;
+ (double)longitude;
+ (NSString *)cityName;
+ (BOOL)fahrenheit;
+ (BOOL)boolForKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (void)setInteger:(NSInteger)v forKey:(NSString *)key;
@end

@interface SBYTheme : NSObject
@property (nonatomic, strong) UIColor *bright, *primary, *dim, *faint, *accent;
@property (nonatomic) BOOL night;
+ (instancetype)current;
+ (void)setAmbientDark:(BOOL)dark;
+ (NSInteger)tintCount;
+ (UIColor *)tintColorForIndex:(NSInteger)i; // nil for 0 = each style's default colours
@end

UIFont *SBYExpandedFont(CGFloat size, UIFontWeight weight);
UIFont *SBYRoundedFont(CGFloat size, UIFontWeight weight);
UIFont *SBYCondensedFont(CGFloat size);

// Draws text with its cap-height box stretched to exactly fill `target`.
void SBYDrawTextFit(NSString *s, UIFont *font, UIColor *color, CGRect target);
// Draws text vertically centered on its cap height. maxWidth<=0 means no limit.
void SBYDrawTextAt(NSString *s, UIFont *font, UIColor *color, CGPoint anchor, NSTextAlignment align, CGFloat maxWidth);
void SBYDrawSymbol(NSString *name, UIColor *color, CGRect rect);
