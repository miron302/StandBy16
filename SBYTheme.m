#import "SBYTheme.h"

@implementation SBYPrefs

+ (NSUserDefaults *)defaults {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:SBY_DOMAIN];
        [d registerDefaults:@{
            @"enabled": @YES,
            @"requireCharging": @YES,
            @"keepAwake": @NO,
            @"nightMode": @0,
            @"nightStart": @21,
            @"nightEnd": @7,
            @"nightBrightness": @0.04,
            @"ambientThreshold": @0.25,
            @"latitude": @51.5072,
            @"longitude": @(-0.1276),
            @"cityName": @"London",
            @"fahrenheit": @NO,
            @"lastView": @1,
            @"lastStyle": @0,
            @"leftStack": @0,
            @"rightStack": @0,
            @"tintIndex": @0,
            @"smartRotate": @YES,
            @"motionToWake": @YES,
            @"notifications": @YES,
            @"nowPlaying": @YES,
            @"timerActivity": @YES,
            @"windowLevel": @10000,
            @"leftOrder": @"0,1,2",
            @"rightOrder": @"3,4,5",
        }];
    });
    return d;
}
+ (BOOL)enabled { return [[self defaults] boolForKey:@"enabled"]; }
+ (BOOL)requireCharging { return [[self defaults] boolForKey:@"requireCharging"]; }
+ (BOOL)keepAwake { return [[self defaults] boolForKey:@"keepAwake"]; }
+ (NSInteger)nightMode { return [[self defaults] integerForKey:@"nightMode"]; }
+ (NSInteger)nightStartHour { return [[self defaults] integerForKey:@"nightStart"]; }
+ (NSInteger)nightEndHour { return [[self defaults] integerForKey:@"nightEnd"]; }
+ (CGFloat)nightBrightness { return [[self defaults] floatForKey:@"nightBrightness"]; }
+ (CGFloat)ambientThreshold { return [[self defaults] floatForKey:@"ambientThreshold"]; }
+ (double)latitude { return [[self defaults] doubleForKey:@"latitude"]; }
+ (double)longitude { return [[self defaults] doubleForKey:@"longitude"]; }
+ (NSString *)cityName { return [[self defaults] stringForKey:@"cityName"] ?: @"London"; }
+ (BOOL)fahrenheit { return [[self defaults] boolForKey:@"fahrenheit"]; }
+ (BOOL)boolForKey:(NSString *)key { return [[self defaults] boolForKey:key]; }
+ (NSInteger)integerForKey:(NSString *)key { return [[self defaults] integerForKey:key]; }
+ (void)setInteger:(NSInteger)v forKey:(NSString *)key { [[self defaults] setInteger:v forKey:key]; }
@end

static BOOL sAmbientDark = NO;

@implementation SBYTheme

+ (void)setAmbientDark:(BOOL)dark { sAmbientDark = dark; }

+ (BOOL)nightActive {
    switch ([SBYPrefs nightMode]) {
        case 1: return YES;
        case 2: return NO;
        case 3: {
            NSInteger h = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
            NSInteger s = [SBYPrefs nightStartHour], e = [SBYPrefs nightEndHour];
            if (s > e) return (h >= s || h < e);
            return (h >= s && h < e);
        }
        default: return sAmbientDark;
    }
}

+ (NSInteger)tintCount { return 9; }

+ (UIColor *)tintColorForIndex:(NSInteger)i {
    switch (i) {
        case 1: return [UIColor colorWithRed:1.00 green:0.23 blue:0.19 alpha:1]; // red
        case 2: return [UIColor colorWithRed:1.00 green:0.58 blue:0.00 alpha:1]; // orange
        case 3: return [UIColor colorWithRed:1.00 green:0.80 blue:0.00 alpha:1]; // yellow
        case 4: return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1]; // green
        case 5: return [UIColor colorWithRed:0.04 green:0.52 blue:1.00 alpha:1]; // blue
        case 6: return [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1]; // purple
        case 7: return [UIColor colorWithRed:1.00 green:0.18 blue:0.33 alpha:1]; // pink
        case 8: return [UIColor colorWithWhite:1.0 alpha:1];                     // white
        default: return nil;
    }
}

+ (instancetype)current {
    SBYTheme *t = [SBYTheme new];
    t.night = [self nightActive];
    if (t.night) {
        // Night mode: everything collapses to one red hue, tint choice is ignored.
        t.bright  = [UIColor colorWithRed:1.0 green:0 blue:0 alpha:1];
        t.primary = [UIColor colorWithRed:0.8 green:0 blue:0 alpha:1];
        t.dim     = [UIColor colorWithRed:0.6 green:0 blue:0 alpha:1];
        t.faint   = [UIColor colorWithRed:0.3 green:0 blue:0 alpha:1];
        t.accent  = [UIColor colorWithRed:0.91 green:0.18 blue:0.13 alpha:1];
        return t;
    }
    UIColor *tint = [self tintColorForIndex:[SBYPrefs integerForKey:@"tintIndex"]];
    if (tint) {
        t.bright = tint;
        t.primary = [tint colorWithAlphaComponent:0.85];
        t.dim = [tint colorWithAlphaComponent:0.55];
        t.faint = [tint colorWithAlphaComponent:0.28];
        t.accent = tint;
    } else {
        t.bright  = [UIColor whiteColor];
        t.primary = [UIColor colorWithWhite:0.92 alpha:1];
        t.dim     = [UIColor colorWithWhite:0.6 alpha:1];
        t.faint   = [UIColor colorWithWhite:0.3 alpha:1];
        t.accent  = [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1];
    }
    return t;
}
@end

#pragma mark - Fonts

UIFont *SBYExpandedFont(CGFloat size, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *d = [base.fontDescriptor fontDescriptorByAddingAttributes:@{
        UIFontDescriptorTraitsAttribute: @{ UIFontWeightTrait: @(weight), UIFontWidthTrait: @(0.4) }
    }];
    UIFont *f = d ? [UIFont fontWithDescriptor:d size:size] : nil;
    return f ?: base;
}

UIFont *SBYRoundedFont(CGFloat size, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *d = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    UIFont *f = d ? [UIFont fontWithDescriptor:d size:size] : nil;
    return f ?: base;
}

UIFont *SBYCondensedFont(CGFloat size) {
    return [UIFont fontWithName:@"DINCondensed-Bold" size:size]
        ?: [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
}

#pragma mark - Drawing helpers

void SBYDrawTextFit(NSString *s, UIFont *font, UIColor *color, CGRect target) {
    if (!s.length) return;
    NSDictionary *a = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
    CGSize sz = [s sizeWithAttributes:a];
    CGFloat cap = font.capHeight;
    if (sz.width <= 0 || cap <= 0) return;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, target.origin.x, target.origin.y);
    CGContextScaleCTM(c, target.size.width / sz.width, target.size.height / cap);
    [s drawAtPoint:CGPointMake(0, -(font.ascender - cap)) withAttributes:a];
    CGContextRestoreGState(c);
}

void SBYDrawTextAt(NSString *s, UIFont *font, UIColor *color, CGPoint anchor, NSTextAlignment align, CGFloat maxWidth) {
    if (!s.length) return;
    NSDictionary *a = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
    CGSize sz = [s sizeWithAttributes:a];
    if (maxWidth > 0 && sz.width > maxWidth) {
        font = [font fontWithSize:font.pointSize * maxWidth / sz.width];
        a = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
        sz = [s sizeWithAttributes:a];
    }
    CGFloat x = anchor.x;
    if (align == NSTextAlignmentCenter) x -= sz.width / 2;
    else if (align == NSTextAlignmentRight) x -= sz.width;
    CGFloat y = anchor.y + font.capHeight / 2 - font.ascender;
    [s drawAtPoint:CGPointMake(x, y) withAttributes:a];
}

void SBYDrawSymbol(NSString *name, UIColor *color, CGRect rect) {
    UIImage *img = [UIImage systemImageNamed:name];
    if (!img) return;
    img = [img imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGSize s = img.size;
    CGFloat k = MIN(rect.size.width / s.width, rect.size.height / s.height);
    CGRect r = CGRectMake(CGRectGetMidX(rect) - s.width * k / 2, CGRectGetMidY(rect) - s.height * k / 2, s.width * k, s.height * k);
    [img drawInRect:r];
}
