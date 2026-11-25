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
@property (nonatomic, strong) UIColor *tint; // normal-mode colour (custom or long-press choice); nil = default look
+ (instancetype)current;
+ (void)setAmbientDark:(BOOL)dark;
+ (NSInteger)tintCount;
+ (UIColor *)tintColorForIndex:(NSInteger)i; // nil for 0 = each style's default colours
+ (UIColor *)customColorForKey:(NSString *)key; // "RRGGBB" hex stored by the Colors settings page
@end

UIColor *SBYColorScaled(UIColor *c, CGFloat k); // multiply brightness (k<1 darker)
UIFont *SBYExpandedFont(CGFloat size, UIFontWeight weight);
UIFont *SBYRoundedFont(CGFloat size, UIFontWeight weight);
UIFont *SBYCondensedFont(CGFloat size);

// Draws text with its cap-height box stretched to exactly fill `target`.
void SBYDrawTextFit(NSString *s, UIFont *font, UIColor *color, CGRect target);
// Draws text vertically centered on its cap height. maxWidth<=0 means no limit.
void SBYDrawTextAt(NSString *s, UIFont *font, UIColor *color, CGPoint anchor, NSTextAlignment align, CGFloat maxWidth);
void SBYDrawSymbol(NSString *name, UIColor *color, CGRect rect);

// Logging goes to the system log AND /var/mobile/Library/Logs/StandBy16.log (open it with Filza, no PC needed).
// Turn it off with the `debug` setting.
void SBYLogf(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
#define SBYLog(fmt, ...) do { if ([SBYPrefs boolForKey:@"debug"]) SBYLogf(fmt, ##__VA_ARGS__); } while (0)
