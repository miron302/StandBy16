#import "SBYPages.h"
#import "SBYServices.h"
#import "SBYWorldData.h"

NSArray<Class> *SBYClockStyleClasses(void) {
    return @[ [SBYDigitalPageView class], [SBYAnalogPageView class], [SBYSolarPageView class],
              [SBYFloatPageView class], [SBYWorldPageView class], [SBYBoldPageView class] ];
}

static CGPoint SBYRayToRect(CGPoint c, CGFloat dx, CGFloat dy, CGRect R) {
    CGFloat tx = fabs(dx) < 1e-6 ? CGFLOAT_MAX : ((dx > 0 ? CGRectGetMaxX(R) : CGRectGetMinX(R)) - c.x) / dx;
    CGFloat ty = fabs(dy) < 1e-6 ? CGFLOAT_MAX : ((dy > 0 ? CGRectGetMaxY(R) : CGRectGetMinY(R)) - c.y) / dy;
    CGFloat t = MIN(tx, ty);
    return CGPointMake(c.x + dx * t, c.y + dy * t);
}

static void SBYLine(CGContextRef c, CGPoint a, CGPoint b, CGFloat w, UIColor *col) {
    CGContextSetStrokeColorWithColor(c, col.CGColor);
    CGContextSetLineWidth(c, w);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextMoveToPoint(c, a.x, a.y);
    CGContextAddLineToPoint(c, b.x, b.y);
    CGContextStrokePath(c);
}

static void SBYDot(CGContextRef c, CGPoint p, CGFloat r, UIColor *col) {
    CGContextSetFillColorWithColor(c, col.CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(p.x - r, p.y - r, r * 2, r * 2));
}

#pragma mark - Base

@implementation SBYPageView
@synthesize theme = _theme;

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor blackColor];
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.clearsContextBeforeDrawing = NO;
    }
    return self;
}
- (SBYTheme *)theme { return _theme ?: [SBYTheme current]; }
- (void)setTheme:(SBYTheme *)t { _theme = t; [self setNeedsDisplay]; }
- (void)tick { [self setNeedsDisplay]; }
- (CGRect)safeRect { return CGRectInset(self.bounds, 46, 8); }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(c, [UIColor blackColor].CGColor);
    CGContextFillRect(c, self.bounds);
    [self drawContent:c bounds:self.bounds];
}
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {}
- (BOOL)handleTapAt:(CGPoint)p { return NO; }
- (BOOL)handleLongPressAt:(CGPoint)p { return NO; }
- (BOOL)isEditing { return NO; }
@end

#pragma mark - Digital

@implementation SBYDigitalPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    UIColor *start = t.night ? [UIColor colorWithRed:0.22 green:0 blue:0 alpha:1] : [UIColor colorWithWhite:0.16 alpha:1];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *cols = @[ (id)start.CGColor, (id)[UIColor blackColor].CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
    CGContextDrawLinearGradient(c, g, CGPointZero, CGPointMake(b.size.width, 0), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    SBYDrawTextAt([SBYServices timeString], SBYExpandedFont(b.size.height * 0.5, UIFontWeightSemibold), t.primary,
                  CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)), NSTextAlignmentCenter, [self safeRect].size.width);
}
@end

#pragma mark - Float

@implementation SBYFloatPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height;
    NSString *time = [SBYServices timeString];
    CGFloat size = h * 0.9;
    UIColor *col = [t.bright colorWithAlphaComponent:0.6];

    CGFloat (^measure)(CGFloat) = ^CGFloat(CGFloat sz) {
        UIFont *f = SBYRoundedFont(sz, UIFontWeightHeavy);
        CGFloat total = 0;
        for (NSUInteger i = 0; i < time.length; i++) {
            NSString *ch = [time substringWithRange:NSMakeRange(i, 1)];
            if ([ch isEqualToString:@":"]) total += sz * 0.2;
            else total += [ch sizeWithAttributes:@{ NSFontAttributeName: f }].width * 0.78;
        }
        return total;
    };
    CGFloat total = measure(size);
    CGFloat maxW = [self safeRect].size.width;
    if (total > maxW) { size *= maxW / total; total = measure(size); }

    UIFont *f = SBYRoundedFont(size, UIFontWeightHeavy);
    CGFloat x = w / 2 - total / 2;
    CGFloat cy = h * 0.46;
    for (NSUInteger i = 0; i < time.length; i++) {
        NSString *ch = [time substringWithRange:NSMakeRange(i, 1)];
        if ([ch isEqualToString:@":"]) {
            CGFloat cx = x + size * 0.1;
            CGFloat r = size * 0.075;
            SBYDot(c, CGPointMake(cx, cy - size * 0.17), r, [t.dim colorWithAlphaComponent:0.9]);
            SBYDot(c, CGPointMake(cx, cy + size * 0.17), r, [t.dim colorWithAlphaComponent:0.9]);
            x += size * 0.2;
        } else {
            CGFloat dw = [ch sizeWithAttributes:@{ NSFontAttributeName: f }].width;
            SBYDrawTextAt(ch, f, col, CGPointMake(x, cy), NSTextAlignmentLeft, 0);
            x += dw * 0.78;
        }
    }
    NSString *alarm = [SBYServices alarmString];
    if (alarm) {
        CGFloat fs = h * 0.065;
        UIFont *af = [UIFont systemFontOfSize:fs weight:UIFontWeightMedium];
        CGFloat ax = CGRectGetMaxX([self safeRect]) - w * 0.2;
        SBYDrawSymbol(@"alarm.fill", t.primary, CGRectMake(ax, h * 0.9 - fs / 2, fs, fs));
        SBYDrawTextAt(alarm, af, t.dim, CGPointMake(ax + fs * 1.3, h * 0.9), NSTextAlignmentLeft, 0);
    }
}
@end

#pragma mark - Analog

@implementation SBYAnalogPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height, s = w / 896.0;
    CGPoint ctr = CGPointMake(w / 2, h / 2);
    CGRect R = CGRectInset(b, 62 * s, 22 * s);

    for (int i = 0; i < 60; i++) {
        CGFloat th = i * M_PI / 30.0;
        CGFloat dx = sin(th), dy = -cos(th);
        CGPoint e = SBYRayToRect(ctr, dx, dy, R);
        BOOL hour = (i % 5 == 0), cardinal = (i % 15 == 0);
        CGFloat len = cardinal ? 80 * s : (hour ? 150 * s : 24 * s);
        CGFloat alpha = 1.0;
        if (!hour) {
            int k = i % 15; k = MIN(k, 15 - k);
            alpha = MAX(0.12, 1.0 - k / 7.0 * 0.88);
        }
        CGPoint a = CGPointMake(e.x - dx * len, e.y - dy * len);
        SBYLine(c, a, e, hour ? 2.4 : 1.6, [t.primary colorWithAlphaComponent:alpha]);
    }

    UIFont *nf = SBYExpandedFont(h * 0.115, UIFontWeightHeavy);
    SBYDrawTextAt(@"12", nf, t.primary, CGPointMake(w * 0.5, h * 0.205), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"3",  nf, t.primary, CGPointMake(w * 0.79, h * 0.5), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"6",  nf, t.primary, CGPointMake(w * 0.5, h * 0.795), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"9",  nf, t.primary, CGPointMake(w * 0.206, h * 0.5), NSTextAlignmentCenter, 0);

    UIFont *cf = [UIFont systemFontOfSize:h * 0.052 weight:UIFontWeightMedium];
    NSString *alarm = [SBYServices alarmString];
    if (alarm) {
        CGFloat is = h * 0.05;
        SBYDrawSymbol(@"alarm.fill", t.primary, CGRectMake(w * 0.29, h * 0.5 - is / 2, is, is));
        SBYDrawTextAt(alarm, cf, t.dim, CGPointMake(w * 0.29 + is * 1.25, h * 0.5), NSTextAlignmentLeft, 0);
    }
    SBYDrawTextAt([SBYServices upperDateString], cf, t.dim, CGPointMake(w * 0.58, h * 0.5), NSTextAlignmentLeft, 0);

    NSDateComponents *dc = [SBYServices nowComponents];
    CGFloat sec = dc.second + dc.nanosecond / 1e9;
    CGFloat min = dc.minute + sec / 60.0;
    CGFloat hr = (dc.hour % 12) + min / 60.0;
    CGFloat ah = hr * M_PI / 6.0, am = min * M_PI / 30.0, as = sec * M_PI / 30.0;

    CGPoint hh = CGPointMake(ctr.x + sin(ah) * h * 0.23, ctr.y - cos(ah) * h * 0.23);
    CGPoint mm = CGPointMake(ctr.x + sin(am) * h * 0.40, ctr.y - cos(am) * h * 0.40);
    SBYLine(c, ctr, hh, h * 0.016, t.accent);
    SBYLine(c, ctr, mm, h * 0.016, t.accent);
    CGPoint st = CGPointMake(ctr.x + sin(as) * h * 0.42, ctr.y - cos(as) * h * 0.42);
    CGPoint sb = CGPointMake(ctr.x - sin(as) * h * 0.06, ctr.y + cos(as) * h * 0.06);
    SBYLine(c, sb, st, 1.6, t.accent);
    SBYDot(c, ctr, 6, t.accent);
    SBYDot(c, ctr, 2.5, [UIColor blackColor]);
}
@end

#pragma mark - World

static double SBYPrefsLat(void);
static double SBYPrefsLon(void);

@implementation SBYWorldPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height;
    CGFloat cell = (w * 0.9) / SBY_WORLD_COLS;
    CGFloat mw = cell * SBY_WORLD_COLS, mh = cell * SBY_WORLD_ROWS;
    CGRect map = CGRectMake((w - mw) / 2, h * 0.1, mw, mh);

    for (int r = 0; r < SBY_WORLD_ROWS; r++) {
        for (int col = 0; col < SBY_WORLD_COLS; col++) {
            if (SBYWorldRows[r][col] != '1') continue;
            SBYDot(c, CGPointMake(map.origin.x + (col + 0.5) * cell, map.origin.y + (r + 0.5) * cell), cell * 0.32, t.dim);
        }
    }

    // Day/night terminator
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *now = [NSDate date];
    NSInteger N = [cal ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitYear forDate:now];
    NSDateComponents *dc = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:now];
    double utc = dc.hour + dc.minute / 60.0;
    double dec = -23.44 * cos(2 * M_PI / 365.0 * (N + 10));
    if (fabs(dec) < 0.5) dec = dec < 0 ? -0.5 : 0.5;
    double decR = dec * M_PI / 180.0;
    double subLon = -15.0 * (utc - 12.0);
    double latSpan = SBY_WORLD_LAT_TOP - SBY_WORLD_LAT_BOT;
    CGContextBeginPath(c);
    BOOL first = YES;
    for (int lon = -180; lon <= 180; lon += 2) {
        double d = (lon - subLon) * M_PI / 180.0;
        double lat = atan(-cos(d) / tan(decR)) * 180.0 / M_PI;
        lat = MAX(SBY_WORLD_LAT_BOT, MIN(SBY_WORLD_LAT_TOP, lat));
        CGPoint p = CGPointMake(map.origin.x + (lon + 180) / 360.0 * mw,
                                map.origin.y + (SBY_WORLD_LAT_TOP - lat) / latSpan * mh);
        if (first) { CGContextMoveToPoint(c, p.x, p.y); first = NO; }
        else CGContextAddLineToPoint(c, p.x, p.y);
    }
    CGContextSetStrokeColorWithColor(c, [t.primary colorWithAlphaComponent:0.75].CGColor);
    CGContextSetLineWidth(c, 2.2);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextStrokePath(c);

    // Location marker
    double lat = SBYPrefsLat(), lon = SBYPrefsLon();
    CGPoint me = CGPointMake(map.origin.x + (lon + 180) / 360.0 * mw,
                             map.origin.y + (SBY_WORLD_LAT_TOP - lat) / latSpan * mh);
    SBYDot(c, me, cell * 0.5, t.primary);

    // Labels
    NSString *time = [SBYServices timeString];
    CGFloat ts = h * 0.055;
    SBYDrawSymbol(@"location.fill", t.primary, CGRectMake(46, h * 0.085 - ts / 2, ts, ts));
    SBYDrawTextAt(time, [UIFont systemFontOfSize:ts weight:UIFontWeightMedium], t.dim,
                  CGPointMake(46 + ts * 1.4, h * 0.085), NSTextAlignmentLeft, 0);
    SBYDrawTextAt([SBYPrefs cityName], [UIFont systemFontOfSize:h * 0.062 weight:UIFontWeightMedium], t.primary,
                  CGPointMake(46, h * 0.80), NSTextAlignmentLeft, 0);
    SBYDrawTextAt(time, [UIFont systemFontOfSize:h * 0.2 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(46, h * 0.9), NSTextAlignmentLeft, 0);
}
static double SBYPrefsLat(void) { return [SBYPrefs latitude]; }
static double SBYPrefsLon(void) { return [SBYPrefs longitude]; }
@end

#pragma mark - Bold

@implementation SBYBoldPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height;
    NSString *time = [SBYServices timeString];
    CGFloat frac = time.length >= 5 ? 1.0 : 0.82;
    SBYDrawTextFit(time, SBYCondensedFont(100), t.dim, CGRectMake(w * 0.14, h * 0.14, w * 0.54 * frac, h * 0.72));

    CGFloat x = w * 0.745;
    UIFont *f = [UIFont systemFontOfSize:h * 0.092 weight:UIFontWeightMedium];
    SBYDrawTextAt([SBYServices upperDateString], f, t.primary, CGPointMake(x, h * 0.17), NSTextAlignmentLeft, 0);
    [SBYServices refreshWeatherIfNeeded];
    NSString *temp = [SBYServices temperatureString];
    if (temp) SBYDrawTextAt(temp, f, t.dim, CGPointMake(x, h * 0.28), NSTextAlignmentLeft, 0);
    NSString *alarm = [SBYServices alarmString];
    if (alarm) {
        CGFloat is = h * 0.085;
        SBYDrawSymbol(@"alarm.fill", t.primary, CGRectMake(x, h * 0.74 - is / 2, is, is));
        SBYDrawTextAt(alarm, f, t.dim, CGPointMake(x, h * 0.86), NSTextAlignmentLeft, 0);
    }
}
@end

#pragma mark - Solar

typedef struct { CGFloat hour; CGFloat top[3]; CGFloat bot[3]; } SBYSky;

static UIColor *SBYSkyColor(const CGFloat *a, const CGFloat *b, CGFloat k) {
    return [UIColor colorWithRed:a[0] + (b[0] - a[0]) * k green:a[1] + (b[1] - a[1]) * k blue:a[2] + (b[2] - a[2]) * k alpha:1];
}

@implementation SBYSolarPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height;
    UIColor *top, *bot;
    if (t.night) {
        top = t.bright; bot = t.dim;
    } else {
        static const SBYSky keys[] = {
            {  0, {0.30, 0.28, 0.65}, {0.10, 0.10, 0.35} },  // night
            {  5, {0.45, 0.35, 0.75}, {0.95, 0.40, 0.45} },  // pre-dawn
            {  8, {1.00, 0.85, 0.45}, {1.00, 0.50, 0.30} },  // morning
            { 13, {1.00, 0.92, 0.45}, {1.00, 0.60, 0.20} },  // midday
            { 18, {1.00, 0.65, 0.30}, {0.85, 0.25, 0.45} },  // golden hour
            { 20, {0.55, 0.35, 0.75}, {0.20, 0.15, 0.45} },  // dusk
            { 24, {0.30, 0.28, 0.65}, {0.10, 0.10, 0.35} },
        };
        NSDateComponents *dc = [SBYServices nowComponents];
        CGFloat hr = dc.hour + dc.minute / 60.0;
        int i = 0;
        while (i < 5 && hr >= keys[i + 1].hour) i++;
        CGFloat k = (hr - keys[i].hour) / (keys[i + 1].hour - keys[i].hour);
        top = SBYSkyColor(keys[i].top, keys[i + 1].top, k);
        bot = SBYSkyColor(keys[i].bot, keys[i + 1].bot, k);
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

    // soft atmospheric glow behind the numerals
    NSArray *glowCols = @[ (id)[top colorWithAlphaComponent:0.20].CGColor, (id)[top colorWithAlphaComponent:0.0].CGColor ];
    CGGradientRef glow = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)glowCols, NULL);
    CGContextDrawRadialGradient(c, glow, CGPointMake(w / 2, h * 0.5), 0, CGPointMake(w / 2, h * 0.5), h * 0.95, 0);
    CGGradientRelease(glow);

    // numerals filled with the sky gradient
    CGRect tr = CGRectMake(0, h * 0.08, w, h * 0.84);
    CGContextSaveGState(c);
    CGContextBeginTransparencyLayerWithRect(c, tr, NULL);
    SBYDrawTextAt([SBYServices timeString], SBYRoundedFont(h * 0.78, UIFontWeightBold), [UIColor whiteColor],
                  CGPointMake(w / 2, h * 0.5), NSTextAlignmentCenter, [self safeRect].size.width);
    CGContextSetBlendMode(c, kCGBlendModeSourceIn);
    NSArray *cols = @[ (id)top.CGColor, (id)bot.CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, tr.origin.y + h * 0.1), CGPointMake(0, CGRectGetMaxY(tr) - h * 0.1), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    CGContextEndTransparencyLayer(c);
    CGContextRestoreGState(c);
    CGColorSpaceRelease(cs);
}
@end

#pragma mark - Widgets

typedef void (*SBYWidgetFn)(CGContextRef, CGRect, SBYTheme *);

// Calendar-style red for the weekday in normal (non-night) mode.
static UIColor *SBYCalendarRed(SBYTheme *t) {
    return t.night ? t.bright : [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1];
}

static void SBYWidgetClock(CGContextRef c, CGRect S, SBYTheme *t) {
    CGPoint ctr = CGPointMake(CGRectGetMidX(S), CGRectGetMidY(S));
    CGFloat k = S.size.width / 250.0;
    CGRect R = CGRectInset(S, 6 * k, 6 * k);
    NSDateComponents *dc = [SBYServices nowComponents];
    CGFloat sec = dc.second + dc.nanosecond / 1e9;
    for (int i = 0; i < 60; i++) {
        CGFloat th = i * M_PI / 30.0, dx = sin(th), dy = -cos(th);
        CGPoint e = SBYRayToRect(ctr, dx, dy, R);
        CGFloat behind = fmod(sec - i + 60.0, 60.0) / 60.0;
        SBYLine(c, CGPointMake(e.x - dx * 12 * k, e.y - dy * 12 * k), e, 2.4 * k, [t.bright colorWithAlphaComponent:MAX(0.07, 1.0 - behind)]);
    }
    NSString *time = [SBYServices timeString];
    CGFloat frac = time.length >= 5 ? 1.0 : 0.82;
    CGFloat tw = S.size.width * 0.62 * frac, th2 = S.size.width * 0.27;
    SBYDrawTextFit(time, SBYCondensedFont(100), t.bright, CGRectMake(ctr.x - tw / 2, ctr.y - th2 / 2, tw, th2));
}

static void SBYWidgetAnalog(CGContextRef c, CGRect S, SBYTheme *t) {
    CGPoint ctr = CGPointMake(CGRectGetMidX(S), CGRectGetMidY(S));
    CGFloat r = S.size.width / 2 * 0.96, k = S.size.width / 250.0;
    for (int i = 0; i < 60; i++) {
        CGFloat th = i * M_PI / 30.0, dx = sin(th), dy = -cos(th);
        BOOL hour = (i % 5 == 0);
        CGFloat len = hour ? r * 0.11 : r * 0.05;
        SBYLine(c, CGPointMake(ctr.x + dx * (r - len), ctr.y + dy * (r - len)), CGPointMake(ctr.x + dx * r, ctr.y + dy * r),
                hour ? 3 * k : 1.4 * k, hour ? t.primary : t.dim);
    }
    UIFont *nf = SBYExpandedFont(r * 0.2, UIFontWeightBold);
    SBYDrawTextAt(@"12", nf, t.primary, CGPointMake(ctr.x, ctr.y - r * 0.68), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"3", nf, t.primary, CGPointMake(ctr.x + r * 0.68, ctr.y), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"6", nf, t.primary, CGPointMake(ctr.x, ctr.y + r * 0.68), NSTextAlignmentCenter, 0);
    SBYDrawTextAt(@"9", nf, t.primary, CGPointMake(ctr.x - r * 0.68, ctr.y), NSTextAlignmentCenter, 0);
    NSDateComponents *dc = [SBYServices nowComponents];
    CGFloat sec = dc.second + dc.nanosecond / 1e9, min = dc.minute + sec / 60.0, hr = (dc.hour % 12) + min / 60.0;
    CGFloat ah = hr * M_PI / 6.0, am = min * M_PI / 30.0, as = sec * M_PI / 30.0;
    SBYLine(c, ctr, CGPointMake(ctr.x + sin(ah) * r * 0.5, ctr.y - cos(ah) * r * 0.5), 6 * k, t.bright);
    SBYLine(c, ctr, CGPointMake(ctr.x + sin(am) * r * 0.8, ctr.y - cos(am) * r * 0.8), 4.5 * k, t.bright);
    SBYLine(c, CGPointMake(ctr.x - sin(as) * r * 0.15, ctr.y + cos(as) * r * 0.15),
            CGPointMake(ctr.x + sin(as) * r * 0.88, ctr.y - cos(as) * r * 0.88), 1.8 * k, t.accent);
    SBYDot(c, ctr, 5 * k, t.accent);
}

static void SBYWidgetBattery(CGContextRef c, CGRect S, SBYTheme *t) {
    CGPoint ctr = CGPointMake(CGRectGetMidX(S), CGRectGetMidY(S));
    CGFloat r = S.size.width * 0.36, lw = S.size.width * 0.075;
    NSInteger pct = [SBYServices batteryPercent];
    CGFloat p = pct < 0 ? 0 : pct / 100.0;
    UIColor *col = t.night ? t.bright : (p <= 0.2 && ![SBYServices isCharging] ? [UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:1] : [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1]);
    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:ctr radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES];
    track.lineWidth = lw;
    [[col colorWithAlphaComponent:0.25] setStroke];
    [track stroke];
    if (p > 0) {
        UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:ctr radius:r startAngle:-M_PI_2 endAngle:-M_PI_2 + 2 * M_PI * p clockwise:YES];
        arc.lineWidth = lw;
        arc.lineCapStyle = kCGLineCapRound;
        [col setStroke];
        [arc stroke];
    }
    SBYDrawTextAt(pct < 0 ? @"--" : [NSString stringWithFormat:@"%ld%%", (long)pct],
                  [UIFont systemFontOfSize:S.size.width * 0.19 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(ctr.x, ctr.y + S.size.width * 0.04), NSTextAlignmentCenter, r * 1.4);
    if ([SBYServices isCharging])
        SBYDrawSymbol(@"bolt.fill", col, CGRectMake(ctr.x - S.size.width * 0.05, ctr.y - S.size.width * 0.2, S.size.width * 0.1, S.size.width * 0.12));
}

static void SBYWidgetDate(CGContextRef c, CGRect S, SBYTheme *t) {
    CGFloat cx = CGRectGetMidX(S);
    UIFont *mf = [UIFont systemFontOfSize:S.size.height * 0.15 weight:UIFontWeightSemibold];
    NSString *wd = [SBYServices weekdayShort], *mo = [SBYServices monthShort];
    CGFloat wdW = [wd sizeWithAttributes:@{ NSFontAttributeName: mf }].width;
    CGFloat spW = [@" " sizeWithAttributes:@{ NSFontAttributeName: mf }].width;
    CGFloat moW = [mo sizeWithAttributes:@{ NSFontAttributeName: mf }].width;
    CGFloat sx = cx - (wdW + spW + moW) / 2;
    CGFloat y = S.origin.y + S.size.height * 0.16;
    SBYDrawTextAt(wd, mf, SBYCalendarRed(t), CGPointMake(sx, y), NSTextAlignmentLeft, 0);
    SBYDrawTextAt(mo, mf, t.dim, CGPointMake(sx + wdW + spW, y), NSTextAlignmentLeft, 0);
    SBYDrawTextAt([SBYServices dayNumber], [UIFont systemFontOfSize:S.size.height * 0.6 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(cx, S.origin.y + S.size.height * 0.6), NSTextAlignmentCenter, S.size.width * 0.9);
}

static void SBYWidgetWeather(CGContextRef c, CGRect S, SBYTheme *t) {
    [SBYServices refreshWeatherIfNeeded];
    CGFloat x = S.origin.x + S.size.width * 0.08, h = S.size.height;
    NSString *sym = [SBYServices weatherSymbol];
    UIColor *iconCol = t.night ? t.bright : [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1];
    if (sym) SBYDrawSymbol(sym, iconCol, CGRectMake(x, S.origin.y + h * 0.08, h * 0.2, h * 0.2));
    SBYDrawTextAt([SBYPrefs cityName], [UIFont systemFontOfSize:h * 0.095 weight:UIFontWeightMedium], t.primary,
                  CGPointMake(x + h * 0.26, S.origin.y + h * 0.18), NSTextAlignmentLeft, S.size.width * 0.55);
    SBYDrawTextAt([SBYServices temperatureString] ?: @"--°", [UIFont systemFontOfSize:h * 0.34 weight:UIFontWeightLight], t.bright,
                  CGPointMake(x, S.origin.y + h * 0.5), NSTextAlignmentLeft, S.size.width * 0.84);
    NSString *cond = [SBYServices weatherCondition];
    if (cond) SBYDrawTextAt(cond, [UIFont systemFontOfSize:h * 0.09 weight:UIFontWeightMedium], t.primary,
                            CGPointMake(x, S.origin.y + h * 0.78), NSTextAlignmentLeft, S.size.width * 0.84);
    NSString *hl = [SBYServices weatherHighLow];
    if (hl) SBYDrawTextAt(hl, [UIFont systemFontOfSize:h * 0.09 weight:UIFontWeightMedium], t.dim,
                          CGPointMake(x, S.origin.y + h * 0.9), NSTextAlignmentLeft, S.size.width * 0.84);
}

static void SBYWidgetWorldTime(CGContextRef c, CGRect S, SBYTheme *t) {
    CGFloat x = S.origin.x + S.size.width * 0.08, h = S.size.height;
    SBYDrawSymbol(@"location.fill", t.primary, CGRectMake(x, S.origin.y + h * 0.11, h * 0.09, h * 0.09));
    SBYDrawTextAt([SBYPrefs cityName], [UIFont systemFontOfSize:h * 0.11 weight:UIFontWeightMedium], t.primary,
                  CGPointMake(x + h * 0.13, S.origin.y + h * 0.155), NSTextAlignmentLeft, S.size.width * 0.7);
    SBYDrawTextAt([SBYServices timeString], [UIFont systemFontOfSize:h * 0.3 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(x, S.origin.y + h * 0.55), NSTextAlignmentLeft, S.size.width * 0.86);
    SBYDrawTextAt(@"Today", [UIFont systemFontOfSize:h * 0.09 weight:UIFontWeightMedium], t.dim,
                  CGPointMake(x, S.origin.y + h * 0.82), NSTextAlignmentLeft, 0);
}

static void SBYWidgetAlarm(CGContextRef c, CGRect S, SBYTheme *t) {
    CGFloat x = S.origin.x + S.size.width * 0.08, h = S.size.height;
    UIColor *orange = t.night ? t.bright : [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1];
    SBYDrawSymbol(@"alarm.fill", orange, CGRectMake(x, S.origin.y + h * 0.08, h * 0.16, h * 0.16));
    SBYDrawTextAt(@"Alarm", [UIFont systemFontOfSize:h * 0.1 weight:UIFontWeightMedium], t.primary,
                  CGPointMake(x + h * 0.21, S.origin.y + h * 0.16), NSTextAlignmentLeft, 0);
    NSString *a = [SBYServices alarmString];
    SBYDrawTextAt(a ?: @"--:--", [UIFont systemFontOfSize:h * 0.3 weight:UIFontWeightSemibold], a ? t.bright : t.dim,
                  CGPointMake(x, S.origin.y + h * 0.55), NSTextAlignmentLeft, S.size.width * 0.86);
    SBYDrawTextAt(a ? @"Next alarm" : @"No alarm set", [UIFont systemFontOfSize:h * 0.09 weight:UIFontWeightMedium], t.dim,
                  CGPointMake(x, S.origin.y + h * 0.82), NSTextAlignmentLeft, 0);
}

#define SBY_WIDGET_N 7
static NSString *const kWidgetNames[SBY_WIDGET_N] = { @"Clock", @"Analog Clock", @"Battery", @"Date", @"Weather", @"World Time", @"Alarm" };
static const SBYWidgetFn kWidgetFns[SBY_WIDGET_N] = { SBYWidgetClock, SBYWidgetAnalog, SBYWidgetBattery, SBYWidgetDate,
                                                       SBYWidgetWeather, SBYWidgetWorldTime, SBYWidgetAlarm };

@implementation SBYWidgetsPageView {
    NSMutableArray<NSNumber *> *_orderL, *_orderR;
    NSInteger _idx[2];
    NSInteger _editing;                 // -1 none, else side being edited
    CFTimeInterval _lastTouch, _lastSmart;
    CGRect _rowRects[SBY_WIDGET_N], _doneRect, _editRect;
}

- (NSMutableArray<NSNumber *> *)loadOrderKey:(NSString *)key {
    NSMutableArray *out = [NSMutableArray array];
    NSString *str = [[SBYPrefs defaults] stringForKey:key] ?: @"";
    for (NSString *p in [str componentsSeparatedByString:@","]) {
        NSInteger v = [p integerValue];
        if (p.length && v >= 0 && v < SBY_WIDGET_N && ![out containsObject:@(v)]) [out addObject:@(v)];
    }
    if (!out.count) [out addObject:@([key isEqualToString:@"leftOrder"] ? 0 : 3)];
    return out;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _orderL = [self loadOrderKey:@"leftOrder"];
        _orderR = [self loadOrderKey:@"rightOrder"];
        _idx[0] = MAX(0, MIN((NSInteger)_orderL.count - 1, [SBYPrefs integerForKey:@"leftStack"]));
        _idx[1] = MAX(0, MIN((NSInteger)_orderR.count - 1, [SBYPrefs integerForKey:@"rightStack"]));
        _editing = -1;
        _lastTouch = CACurrentMediaTime();
    }
    return self;
}

- (NSMutableArray<NSNumber *> *)orderForSide:(int)s { return s == 0 ? _orderL : _orderR; }
- (BOOL)isEditing { return _editing >= 0; }

- (CGRect)stackRectForSide:(int)s bounds:(CGRect)b {
    CGFloat side = MIN(b.size.height * 0.84, b.size.width * 0.42);
    CGFloat cx = s == 0 ? b.size.width * 0.27 : b.size.width * 0.73;
    return CGRectMake(cx - side / 2, b.size.height / 2 - side / 2, side, side);
}

- (void)redrawDissolve {
    [UIView transitionWithView:self duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self setNeedsDisplay]; } completion:nil];
}

- (void)scrollStack:(int)side by:(int)delta {
    _lastTouch = CACurrentMediaTime();
    NSInteger n = [self orderForSide:side].count;
    NSInteger ni = MAX(0, MIN(n - 1, _idx[side] + delta));
    if (ni == _idx[side]) return;
    _idx[side] = ni;
    [SBYPrefs setInteger:ni forKey:side == 0 ? @"leftStack" : @"rightStack"];
    [self redrawDissolve];
}

#pragma mark Smart Rotate

- (void)showWidget:(NSInteger)wid onSide:(int)s {
    NSUInteger i = [[self orderForSide:s] indexOfObject:@(wid)];
    if (i == NSNotFound || _idx[s] == (NSInteger)i) return;
    _idx[s] = i;
    [self redrawDissolve];
}

- (void)smartRotate {
    if (![SBYPrefs boolForKey:@"smartRotate"] || _editing >= 0) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastTouch < 300 || now - _lastSmart < 30) return; // leave it alone for 5 min after you touch it
    _lastSmart = now;
    NSInteger want = 3; // Date
    NSDate *al = [SBYServices nextAlarmDate];
    NSInteger hr = [SBYServices nowComponents].hour;
    if (al && [al timeIntervalSinceNow] < 3600) want = 6;   // alarm within the hour
    else if (hr >= 5 && hr < 10) want = 4;                   // mornings: weather
    [self showWidget:0 onSide:0];
    [self showWidget:want onSide:1];
}

- (void)tick { [self smartRotate]; [super tick]; }

#pragma mark Editing (long-press a stack)

- (BOOL)handleLongPressAt:(CGPoint)p {
    _editing = p.x < self.bounds.size.width / 2 ? 0 : 1;
    _lastTouch = CACurrentMediaTime();
    [self setNeedsDisplay];
    return YES;
}

- (void)saveOrder:(int)s {
    NSString *key = s == 0 ? @"leftOrder" : @"rightOrder";
    [[SBYPrefs defaults] setObject:[[self orderForSide:s] componentsJoinedByString:@","] forKey:key];
    NSInteger n = [self orderForSide:s].count;
    _idx[s] = MAX(0, MIN(n - 1, _idx[s]));
    [SBYPrefs setInteger:_idx[s] forKey:s == 0 ? @"leftStack" : @"rightStack"];
}

- (BOOL)handleTapAt:(CGPoint)p {
    if (_editing < 0) return NO;
    int s = (int)_editing;
    if (CGRectContainsPoint(_doneRect, p) || !CGRectContainsPoint(_editRect, p)) {
        _editing = -1;
        [self setNeedsDisplay];
        return YES;
    }
    for (int i = 0; i < SBY_WIDGET_N; i++) {
        if (!CGRectContainsPoint(_rowRects[i], p)) continue;
        NSMutableArray *o = [self orderForSide:s];
        if ([o containsObject:@(i)]) { if (o.count > 1) [o removeObject:@(i)]; }
        else [o addObject:@(i)];
        [self saveOrder:s];
        [self setNeedsDisplay];
        break;
    }
    return YES;
}

- (void)drawEditPanel:(CGContextRef)c rect:(CGRect)S side:(int)s theme:(SBYTheme *)t {
    _editRect = S;
    UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:S cornerRadius:S.size.width * 0.08];
    [[t.faint colorWithAlphaComponent:0.45] setFill];
    [bg fill];
    CGFloat h = S.size.height, x = S.origin.x + S.size.width * 0.07;
    SBYDrawTextAt(@"Edit Stack", [UIFont systemFontOfSize:h * 0.075 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(x, S.origin.y + h * 0.1), NSTextAlignmentLeft, 0);
    UIColor *blue = t.night ? t.bright : [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1];
    CGPoint dp = CGPointMake(CGRectGetMaxX(S) - S.size.width * 0.07, S.origin.y + h * 0.1);
    SBYDrawTextAt(@"Done", [UIFont systemFontOfSize:h * 0.075 weight:UIFontWeightSemibold], blue, dp, NSTextAlignmentRight, 0);
    _doneRect = CGRectMake(dp.x - h * 0.3, S.origin.y, h * 0.3 + S.size.width * 0.07, h * 0.2);
    NSMutableArray *o = [self orderForSide:s];
    CGFloat rowH = h * 0.105, y0 = S.origin.y + h * 0.2;
    for (int i = 0; i < SBY_WIDGET_N; i++) {
        CGFloat cy = y0 + i * rowH + rowH / 2;
        _rowRects[i] = CGRectMake(S.origin.x, cy - rowH / 2, S.size.width, rowH);
        BOOL on = [o containsObject:@(i)];
        UIColor *green = t.night ? t.bright : [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1];
        UIColor *red = t.night ? t.bright : [UIColor colorWithRed:1 green:0.23 blue:0.19 alpha:1];
        SBYDrawSymbol(on ? @"minus.circle.fill" : @"plus.circle.fill", on ? red : green,
                      CGRectMake(x, cy - rowH * 0.36, rowH * 0.72, rowH * 0.72));
        SBYDrawTextAt(kWidgetNames[i], [UIFont systemFontOfSize:h * 0.07 weight:UIFontWeightMedium], on ? t.bright : t.dim,
                      CGPointMake(x + rowH, cy), NSTextAlignmentLeft, S.size.width * 0.7);
    }
}

#pragma mark Drawing

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    for (int s = 0; s < 2; s++) {
        CGRect S = [self stackRectForSide:s bounds:b];
        NSMutableArray *o = [self orderForSide:s];
        if (_editing == s) { [self drawEditPanel:c rect:S side:s theme:t]; continue; }
        NSInteger wid = [o[MIN((NSUInteger)_idx[s], o.count - 1)] integerValue];
        kWidgetFns[wid](c, S, t);
        CGFloat dx = CGRectGetMaxX(S) + 12, gap = 12;
        CGFloat y0 = b.size.height / 2 - (o.count - 1) * gap / 2;
        for (NSUInteger i = 0; i < o.count; i++)
            SBYDot(c, CGPointMake(dx, y0 + i * gap), 2.6, (NSInteger)i == _idx[s] ? t.primary : t.faint);
    }
}
@end

#pragma mark - Now Playing (full-screen takeover while media plays)

@implementation SBYNowPlayingPageView {
    CGRect _ctrl[3]; // previous, play/pause, next
}

- (BOOL)handleTapAt:(CGPoint)p {
    int cmds[3] = { 5, 2, 4 };
    for (int i = 0; i < 3; i++) {
        if (CGRectContainsPoint(CGRectInset(_ctrl[i], -14, -14), p)) {
            [SBYServices sendMediaCommand:cmds[i]];
            return YES;
        }
    }
    return NO;
}

static NSString *SBYClockText(double sec) {
    long s = lround(MAX(0, sec));
    return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    NSDictionary *np = [SBYServices nowPlaying];
    if (!np) return;
    CGFloat w = b.size.width, h = b.size.height;
    CGFloat side = h * 0.72;
    CGRect art = CGRectMake(MAX(46, w * 0.07), (h - side) / 2, side, side);
    UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:art cornerRadius:side * 0.06];

    CGContextSaveGState(c);
    [clip addClip];
    UIImage *img = np[@"artwork"];
    if (img) {
        [img drawInRect:art];
        if (t.night) { // collapse artwork to the red monochrome treatment
            CGContextSetBlendMode(c, kCGBlendModeColor);
            CGContextSetFillColorWithColor(c, t.bright.CGColor);
            CGContextFillRect(c, art);
        }
    } else {
        [[t.faint colorWithAlphaComponent:0.5] setFill];
        UIRectFill(art);
        SBYDrawSymbol(@"music.note", t.primary, CGRectInset(art, side * 0.33, side * 0.33));
    }
    CGContextRestoreGState(c);

    CGFloat x0 = CGRectGetMaxX(art) + w * 0.05, x1 = w - 46, tw = x1 - x0;
    SBYDrawTextAt(np[@"title"], [UIFont systemFontOfSize:h * 0.085 weight:UIFontWeightSemibold], t.bright,
                  CGPointMake(x0, h * 0.26), NSTextAlignmentLeft, tw);
    if (np[@"artist"])
        SBYDrawTextAt(np[@"artist"], [UIFont systemFontOfSize:h * 0.07 weight:UIFontWeightMedium], t.dim,
                      CGPointMake(x0, h * 0.37), NSTextAlignmentLeft, tw);

    double dur = [np[@"duration"] doubleValue], el = [np[@"elapsed"] doubleValue];
    CGFloat by = h * 0.55;
    CGRect track = CGRectMake(x0, by - 2.5, tw, 5);
    [[t.faint colorWithAlphaComponent:0.8] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:2.5] fill];
    if (dur > 0) {
        CGRect fill = track; fill.size.width = tw * MIN(1, el / dur);
        [t.primary setFill];
        [[UIBezierPath bezierPathWithRoundedRect:fill cornerRadius:2.5] fill];
        UIFont *sf = [UIFont systemFontOfSize:h * 0.045 weight:UIFontWeightMedium];
        SBYDrawTextAt(SBYClockText(el), sf, t.dim, CGPointMake(x0, by + h * 0.07), NSTextAlignmentLeft, 0);
        SBYDrawTextAt([@"-" stringByAppendingString:SBYClockText(dur - el)], sf, t.dim, CGPointMake(x1, by + h * 0.07), NSTextAlignmentRight, 0);
    }

    CGFloat cs = h * 0.11, cy = h * 0.8, cx = x0 + tw / 2, gap = tw * 0.28;
    NSString *names[3] = { @"backward.fill", [np[@"playing"] boolValue] ? @"pause.fill" : @"play.fill", @"forward.fill" };
    for (int i = 0; i < 3; i++) {
        CGFloat px = cx + (i - 1) * gap;
        _ctrl[i] = CGRectMake(px - cs / 2, cy - cs / 2, cs, cs);
        SBYDrawSymbol(names[i], t.bright, _ctrl[i]);
    }
}
@end

#pragma mark - Timer (Live Activity style takeover)

@implementation SBYTimerPageView
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    NSTimeInterval rem = 0, tot = 1;
    if (![SBYServices timerRemaining:&rem total:&tot]) return;
    CGFloat w = b.size.width, h = b.size.height;
    UIColor *orange = t.night ? t.bright : [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1];

    CGPoint ctr = CGPointMake(w * 0.24, h * 0.5);
    CGFloat r = h * 0.3, lw = h * 0.045;
    UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:ctr radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES];
    track.lineWidth = lw;
    [[orange colorWithAlphaComponent:0.25] setStroke];
    [track stroke];
    CGFloat p = tot > 0 ? MIN(1, rem / tot) : 0;
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:ctr radius:r startAngle:-M_PI_2 endAngle:-M_PI_2 + 2 * M_PI * p clockwise:YES];
    arc.lineWidth = lw;
    arc.lineCapStyle = kCGLineCapRound;
    [orange setStroke];
    [arc stroke];
    SBYDrawSymbol(@"timer", orange, CGRectMake(ctr.x - r * 0.35, ctr.y - r * 0.35, r * 0.7, r * 0.7));

    long s = lround(rem), hh = s / 3600, mm = (s % 3600) / 60, ss = s % 60;
    NSString *txt = hh > 0 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", hh, mm, ss] : [NSString stringWithFormat:@"%ld:%02ld", mm, ss];
    SBYDrawTextAt(@"Timer", [UIFont systemFontOfSize:h * 0.07 weight:UIFontWeightSemibold], orange,
                  CGPointMake(w * 0.45, h * 0.24), NSTextAlignmentLeft, 0);
    SBYDrawTextAt(txt, SBYExpandedFont(h * 0.42, UIFontWeightSemibold), t.bright,
                  CGPointMake(w * 0.45, h * 0.55), NSTextAlignmentLeft, w * 0.5);
}
@end
