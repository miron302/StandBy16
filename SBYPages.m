#import "SBYPages.h"
#import "SBYServices.h"
#import "SBYWorldData.h"

NSArray<Class> *SBYClockStyleClasses(void) {
    return @[ [SBYDigitalPageView class], [SBYAnalogPageView class], [SBYSolarPageView class],
              [SBYFloatPageView class], [SBYFloatColorPageView class], [SBYWorldPageView class], [SBYBoldPageView class] ];
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

static CGFloat SBYEaseOutBack(CGFloat x) {
    x = MAX(0, MIN(1, x));
    const CGFloat c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2);
}

static CGFloat SBYEaseInOutCubic(CGFloat x) {
    x = MAX(0, MIN(1, x));
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;
}

static BOOL sAnimationsSuspended;

#pragma mark - Base

@implementation SBYPageView {
    NSString *_lastTime, *_prevTime;
    CFTimeInterval _appearT, _rollT0;
    NSTimer *_liveTimer, *_rollTimer;
}
+ (void)setAnimationsSuspended:(BOOL)suspended { sAnimationsSuspended = suspended; }
@synthesize theme = _theme;

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor blackColor];
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.clearsContextBeforeDrawing = NO;
        _minuteTransition = YES;
    }
    return self;
}
- (SBYTheme *)theme { return _theme ?: [SBYTheme current]; }
- (void)setTheme:(SBYTheme *)t { _theme = t; [self setNeedsDisplay]; }
- (void)tick {
    NSString *ts = [SBYServices timeString];
    NSString *old = _lastTime;
    BOOL changed = old && ![ts isEqualToString:old];
    _lastTime = ts;
    if (changed && self.window) {
        if (_rollsDigits && ts.length == old.length) {
            // changed digits roll up and fade, the new ones rise in from below
            _prevTime = old;
            _rollT0 = CACurrentMediaTime();
            [_rollTimer invalidate];
            _rollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 target:self selector:@selector(rollStep) userInfo:nil repeats:YES];
            [self setNeedsDisplay];
            return;
        }
        if (_minuteTransition) {
            // soft cross-dissolve when the time changes, like iOS does
            [UIView transitionWithView:self duration:0.4 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ [self setNeedsDisplay]; } completion:nil];
            return;
        }
    }
    [self setNeedsDisplay];
}

- (void)rollStep {
    [self setNeedsDisplay];
    if (CACurrentMediaTime() - _rollT0 > 0.6) { [_rollTimer invalidate]; _rollTimer = nil; _prevTime = nil; }
}

// Pages that move continuously (floating digits, sweeping hands, progress) get a light redraw timer while visible.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_liveTimer invalidate];
    _liveTimer = nil;
    if (self.window) {
        _appearT = CACurrentMediaTime();
        if (_liveFPS > 0)
            _liveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / _liveFPS target:self selector:@selector(liveStep) userInfo:nil repeats:YES];
    } else {
        [_rollTimer invalidate];
        _rollTimer = nil;
        _prevTime = nil;
    }
}
- (void)liveStep { if (!sAnimationsSuspended) [self setNeedsDisplay]; }
- (CFTimeInterval)pageAge { return CACurrentMediaTime() - _appearT; }

- (void)drawChar:(NSString *)ch index:(NSUInteger)i order:(NSInteger)order at:(CGPoint)pt font:(UIFont *)font color:(UIColor *)color {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat cw = [ch sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    CGContextSaveGState(c);
    if (order >= 0) { // entrance: each digit pops in with a little overshoot, one after another
        CFTimeInterval a = self.pageAge - order * 0.07;
        CGFloat s = 0.55 + 0.45 * SBYEaseOutBack(a / 0.6);
        CGContextSetAlpha(c, MAX(0, MIN(1, a / 0.25)));
        CGContextTranslateCTM(c, pt.x + cw / 2, pt.y);
        CGContextScaleCTM(c, s, s);
        CGContextTranslateCTM(c, -(pt.x + cw / 2), -pt.y);
    }
    NSString *old = (_prevTime && i < _prevTime.length) ? [_prevTime substringWithRange:NSMakeRange(i, 1)] : nil;
    CGFloat prog = old ? SBYEaseInOutCubic((CACurrentMediaTime() - _rollT0) / 0.5) : 1;
    if (!old || prog >= 1 || [old isEqualToString:ch]) {
        SBYDrawTextAt(ch, font, color, pt, NSTextAlignmentLeft, 0);
    } else {
        CGFloat amp = font.pointSize * 0.30;
        CGContextSaveGState(c);
        CGContextSetAlpha(c, (1 - prog) * 1.0);
        SBYDrawTextAt(old, font, color, CGPointMake(pt.x, pt.y - amp * prog), NSTextAlignmentLeft, 0);
        CGContextRestoreGState(c);
        CGContextSaveGState(c);
        CGContextSetAlpha(c, prog);
        SBYDrawTextAt(ch, font, color, CGPointMake(pt.x, pt.y + amp * (1 - prog)), NSTextAlignmentLeft, 0);
        CGContextRestoreGState(c);
    }
    CGContextRestoreGState(c);
}
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
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.rollsDigits = YES; self.minuteTransition = NO; }
    return self;
}
- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    UIColor *start = t.night ? SBYColorScaled(t.bright, 0.22) : [UIColor colorWithWhite:0.16 alpha:1];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *cols = @[ (id)start.CGColor, (id)[UIColor blackColor].CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
    CGContextDrawLinearGradient(c, g, CGPointZero, CGPointMake(b.size.width, 0), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    NSString *time = [SBYServices timeString];
    CGFloat size = b.size.height * 0.5, maxW = [self safeRect].size.width;
    UIFont *font = SBYExpandedFont(size, UIFontWeightSemibold);
    CGFloat total = 0;
    for (NSUInteger i = 0; i < time.length; i++)
        total += [[time substringWithRange:NSMakeRange(i, 1)] sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    if (total > maxW) { size *= maxW / total; font = SBYExpandedFont(size, UIFontWeightSemibold); total = maxW; }
    CGFloat x = CGRectGetMidX(b) - total / 2, y = CGRectGetMidY(b);
    for (NSUInteger i = 0; i < time.length; i++) {
        NSString *ch = [time substringWithRange:NSMakeRange(i, 1)];
        [self drawChar:ch index:i order:-1 at:CGPointMake(x, y) font:font color:t.primary];
        x += [ch sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    }
}
@end

#pragma mark - Float

@implementation SBYFloatPageView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.rollsDigits = YES; self.minuteTransition = NO; self.liveFPS = 24; }
    return self;
}
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
            [self drawChar:ch index:i order:(NSInteger)i at:CGPointMake(x, cy) font:f color:col];
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

#pragma mark - Float (colour): two-tone floating digits + battery ring + alarm

static UIColor *SBYScaleColor(UIColor *c, CGFloat k) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:MIN(1, r * k) green:MIN(1, g * k) blue:MIN(1, b * k) alpha:a];
}

@implementation SBYFloatColorPageView {
    CFTimeInterval _ringT0;
    BOOL _lastCharging;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.rollsDigits = YES; self.minuteTransition = NO; self.liveFPS = 24; }
    return self;
}

// The base class runs a light 24fps timer while this page is on screen: digits drift, the battery ring draws in.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        _ringT0 = CACurrentMediaTime();
        _lastCharging = [SBYServices isCharging];
    }
}

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    CGFloat w = b.size.width, h = b.size.height;
    CFTimeInterval age = self.pageAge;

    // palette: blue by default, the chosen colour if there is one, red at night
    UIColor *dark, *light, *dot;
    if (t.night) {
        dark = SBYColorScaled(t.bright, 0.55);
        light = [t.bright colorWithAlphaComponent:0.9];
        dot = SBYColorScaled(t.bright, 0.8);
    } else {
        UIColor *tint = t.tint;
        if (tint) { dark = SBYScaleColor(tint, 0.62); light = [tint colorWithAlphaComponent:0.92]; }
        else { dark = [UIColor colorWithRed:0.16 green:0.37 blue:0.70 alpha:1]; light = [UIColor colorWithRed:0.40 green:0.63 blue:0.90 alpha:0.93]; }
        dot = [UIColor colorWithWhite:0.76 alpha:1];
    }

    NSString *time = [SBYServices timeString];
    CGFloat size = h * 0.96;
    CGFloat step = 0.66;
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSUInteger i = 0; i < time.length; i++) [tokens addObject:[time substringWithRange:NSMakeRange(i, 1)]];

    CGFloat (^measure)(CGFloat) = ^CGFloat(CGFloat sz) {
        UIFont *f = SBYRoundedFont(sz, UIFontWeightHeavy);
        CGFloat total = 0;
        for (NSString *ch in tokens) {
            if ([ch isEqualToString:@":"]) total += sz * 0.2;
            else total += [ch sizeWithAttributes:@{ NSFontAttributeName: f }].width * step;
        }
        return total + sz * 0.1;
    };
    CGFloat total = measure(size), maxW = [self safeRect].size.width * 0.96;
    if (total > maxW) { size *= maxW / total; total = measure(size); }
    UIFont *font = SBYRoundedFont(size, UIFontWeightHeavy);

    // layout pass
    CGFloat x = w / 2 - total / 2;
    CGFloat cy = h * 0.47;
    NSMutableArray *digits = [NSMutableArray array];  // {char, x, digit number, index in the time string}
    CGFloat colonX = 0;
    int di = 0;
    for (NSUInteger ti = 0; ti < tokens.count; ti++) {
        NSString *ch = tokens[ti];
        if ([ch isEqualToString:@":"]) { colonX = x + size * 0.1; x += size * 0.2; continue; }
        [digits addObject:@[ ch, @(x), @(di++), @(ti) ]];
        x += [ch sizeWithAttributes:@{ NSFontAttributeName: font }].width * step;
    }
    // dark digits first, then the light ones overlap them, like the real Float
    for (int pass = 0; pass < 2; pass++) {
        for (NSArray *d in digits) {
            int idx = [d[2] intValue];
            if ((idx % 2 == 0) != (pass == 0)) continue;
            CGFloat dx = cos(age * 0.7 + idx * 0.9) * h * 0.006;
            CGFloat dy = sin(age * 0.9 + idx * 1.3) * h * 0.012;   // gentle floating
            [self drawChar:d[0] index:[d[3] unsignedIntegerValue] order:idx at:CGPointMake([d[1] floatValue] + dx, cy + dy) font:font color:(pass == 0 ? dark : light)];
        }
    }
    if (colonX > 0) {
        CGFloat r = size * 0.075;
        CGFloat dy = sin(age * 0.9 + 2.1) * h * 0.01;
        SBYDot(c, CGPointMake(colonX, cy - size * 0.17 + dy), r, dot);
        SBYDot(c, CGPointMake(colonX, cy + size * 0.17 + dy), r, dot);
    }

    // Battery ring (top right): draws in clockwise, a bolt pops while charging, then it holds for 3 seconds after the
    // animation finishes and fades away. Plugging in or unplugging replays it.
    BOOL chargingNow = [SBYServices isCharging];
    if (chargingNow != _lastCharging) { _lastCharging = chargingNow; _ringT0 = CACurrentMediaTime(); }
    CFTimeInterval rage = CACurrentMediaTime() - _ringT0;
    const CFTimeInterval kDelay = 0.35, kDrawTime = 1.0, kHold = 3.0, kFade = 0.5;
    CGFloat ringAlpha = 1.0 - MAX(0, MIN(1, (rage - (kDelay + kDrawTime + kHold)) / kFade));
    if (ringAlpha > 0.001) {
        CGFloat rr = h * 0.075, rcx = w - MAX(46, w * 0.055) - rr, rcy = h * 0.115;
        NSInteger pct = [SBYServices batteryPercent];
        UIColor *green = t.night ? t.bright : [UIColor colorWithRed:0.39 green:0.82 blue:0.35 alpha:1];
        CGFloat draw = MIN(1, SBYEaseOutBack(MAX(0, (rage - kDelay) / kDrawTime)));
        CGFloat pf = pct < 0 ? 0 : pct / 100.0;
        CGContextSaveGState(c);
        CGContextSetAlpha(c, ringAlpha);
        UIBezierPath *track = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rcx, rcy) radius:rr startAngle:0 endAngle:2 * M_PI clockwise:YES];
        track.lineWidth = rr * 0.2;
        [[green colorWithAlphaComponent:0.22 * MIN(1, draw * 2)] setStroke];
        [track stroke];
        if (pf > 0 && draw > 0) {
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rcx, rcy) radius:rr startAngle:-M_PI_2
                                                             endAngle:-M_PI_2 + 2 * M_PI * pf * draw clockwise:YES];
            arc.lineWidth = rr * 0.2;
            arc.lineCapStyle = kCGLineCapRound;
            [green setStroke];
            [arc stroke];
        }
        if (chargingNow && rage < 2.8) {
            CGFloat s = SBYEaseOutBack((rage - 0.9) / 0.5);
            if (s > 0) SBYDrawSymbol(@"bolt.fill", green, CGRectMake(rcx - rr * 0.32 * s, rcy - rr * 0.45 * s, rr * 0.64 * s, rr * 0.9 * s));
        } else if (pct >= 0) {
            SBYDrawTextAt([NSString stringWithFormat:@"%ld", (long)pct], [UIFont systemFontOfSize:rr * 0.95 weight:UIFontWeightSemibold],
                          green, CGPointMake(rcx, rcy), NSTextAlignmentCenter, rr * 1.5);
        }
        CGContextRestoreGState(c);
    }

    // alarm (bottom right)
    NSString *alarm = [SBYServices alarmString];
    if (alarm) {
        CGFloat fs = h * 0.058;
        CGFloat ax = w * 0.765, ay = h * 0.885;
        UIColor *red = t.night ? t.bright : [UIColor colorWithRed:0.92 green:0.27 blue:0.20 alpha:1];
        SBYDrawSymbol(@"alarm.fill", red, CGRectMake(ax, ay - fs * 0.55, fs * 1.1, fs * 1.1));
        SBYDrawTextAt(alarm, [UIFont italicSystemFontOfSize:fs], t.night ? t.primary : [UIColor whiteColor],
                      CGPointMake(ax + fs * 1.4, ay + fs * 0.1), NSTextAlignmentLeft, 0);
    }
}
@end

#pragma mark - Analog

@implementation SBYAnalogPageView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.minuteTransition = NO; self.liveFPS = 30; }  // smooth sweeping second hand
    return self;
}
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
        self.minuteTransition = NO;
        self.liveFPS = 12; // smooth ring sweep in the clock widget
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

// A 12x12 copy of the artwork; scaled up with smoothing it becomes a colour glow for the backdrop.
static UIImage *SBYTinyImage(UIImage *src) {
    if (!src) return nil;
    CGSize s = CGSizeMake(12, 12);
    UIGraphicsBeginImageContextWithOptions(s, YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationMedium);
    [src drawInRect:CGRectMake(0, 0, s.width, s.height)];
    UIImage *o = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return o;
}

static NSString *SBYClockText(double sec) {
    long s = lround(MAX(0, sec));
    return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60];
}

@implementation SBYNowPlayingPageView {
    CGRect _ctrl[3]; // previous, play/pause, next
    UIImage *_lastArt, *_tiny;
    NSString *_lastTitle;
    NSInteger _pressed;
    CGFloat _artScale;
    NSTimer *_animTimer;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.minuteTransition = NO;
        self.liveFPS = 20; // smooth progress bar
        _artScale = 1;
        _pressed = -1;
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)v {
    [super willMoveToSuperview:v];
    if (!v) { [_animTimer invalidate]; _animTimer = nil; }
}

- (CGFloat)targetScale {
    return [[SBYServices nowPlaying][@"playing"] boolValue] ? 1.0 : 0.86; // artwork shrinks when paused
}

- (void)tick {
    NSString *title = [SBYServices nowPlaying][@"title"];
    if (title && _lastTitle && ![title isEqualToString:_lastTitle] && self.window) {
        _lastTitle = title; // new track: dissolve to the new artwork and text
        [UIView transitionWithView:self duration:0.45 options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ [self setNeedsDisplay]; } completion:nil];
    } else {
        _lastTitle = title;
        [super tick];
    }
    if (fabs(_artScale - [self targetScale]) > 0.003 && !_animTimer)
        _animTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 target:self selector:@selector(animStep) userInfo:nil repeats:YES];
}

- (void)animStep {
    CGFloat target = [self targetScale];
    _artScale += (target - _artScale) * 0.16;
    if (fabs(_artScale - target) < 0.003) { _artScale = target; [_animTimer invalidate]; _animTimer = nil; }
    [self setNeedsDisplay];
}

- (BOOL)handleTapAt:(CGPoint)p {
    int cmds[3] = { 5, 2, 4 };
    for (int i = 0; i < 3; i++) {
        if (CGRectContainsPoint(CGRectInset(_ctrl[i], -16, -16), p)) {
            _pressed = i;
            [self setNeedsDisplay];
            [SBYServices sendMediaCommand:cmds[i]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self->_pressed = -1;
                [self setNeedsDisplay];
            });
            return YES;
        }
    }
    return NO;
}

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    NSDictionary *np = [SBYServices nowPlaying];
    if (!np) return;
    CGFloat w = b.size.width, h = b.size.height;
    UIImage *img = np[@"artwork"];
    if (img != _lastArt) { _lastArt = img; _tiny = SBYTinyImage(img); }

    // Backdrop: a soft glow taken from the artwork (red glow in night mode)
    if (t.night) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSArray *cols = @[ (id)[t.bright colorWithAlphaComponent:0.22].CGColor, (id)[t.bright colorWithAlphaComponent:0].CGColor ];
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
        CGContextDrawRadialGradient(c, g, CGPointMake(w * 0.25, h * 0.5), 0, CGPointMake(w * 0.25, h * 0.5), h, 0);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);
    } else if (_tiny) {
        CGContextSaveGState(c);
        CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
        [_tiny drawInRect:b blendMode:kCGBlendModeNormal alpha:0.6];
        CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
        CGContextFillRect(c, b);
        CGContextRestoreGState(c);
    }

    // Artwork (scales down while paused), with a soft drop shadow
    CGFloat full = h * 0.7;
    CGFloat side = full * _artScale;
    CGFloat left = MAX(46, w * 0.06);
    CGRect art = CGRectMake(left + (full - side) / 2, (h - side) / 2, side, side);
    UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:art cornerRadius:side * 0.07];
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 10), 28, [UIColor colorWithWhite:0 alpha:0.55].CGColor);
    [[UIColor blackColor] setFill];
    [clip fill];
    CGContextRestoreGState(c);

    CGContextSaveGState(c);
    [clip addClip];
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

    CGFloat x0 = left + full + w * 0.05, x1 = w - 46, tw = x1 - x0;
    SBYDrawTextAt(np[@"title"], [UIFont systemFontOfSize:h * 0.085 weight:UIFontWeightBold], t.bright,
                  CGPointMake(x0, h * 0.27), NSTextAlignmentLeft, tw);
    if (np[@"artist"])
        SBYDrawTextAt(np[@"artist"], [UIFont systemFontOfSize:h * 0.07 weight:UIFontWeightMedium], [t.primary colorWithAlphaComponent:0.7],
                      CGPointMake(x0, h * 0.38), NSTextAlignmentLeft, tw);

    // Progress
    double dur = [np[@"duration"] doubleValue], el = [np[@"elapsed"] doubleValue];
    CGFloat by = h * 0.56;
    CGRect track = CGRectMake(x0, by - 2.5, tw, 5);
    [[t.primary colorWithAlphaComponent:0.28] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:track cornerRadius:2.5] fill];
    if (dur > 0) {
        CGRect fill = track; fill.size.width = MAX(5, tw * MIN(1, el / dur));
        [t.bright setFill];
        [[UIBezierPath bezierPathWithRoundedRect:fill cornerRadius:2.5] fill];
        UIFont *sf = [UIFont monospacedDigitSystemFontOfSize:h * 0.045 weight:UIFontWeightMedium];
        SBYDrawTextAt(SBYClockText(el), sf, [t.primary colorWithAlphaComponent:0.7], CGPointMake(x0, by + h * 0.07), NSTextAlignmentLeft, 0);
        SBYDrawTextAt([@"-" stringByAppendingString:SBYClockText(dur - el)], sf, [t.primary colorWithAlphaComponent:0.7],
                      CGPointMake(x1, by + h * 0.07), NSTextAlignmentRight, 0);
    }

    // Controls (the pressed one shrinks briefly)
    CGFloat cs = h * 0.115, cy = h * 0.8, cx = x0 + tw / 2, gap = tw * 0.28;
    NSString *names[3] = { @"backward.fill", [np[@"playing"] boolValue] ? @"pause.fill" : @"play.fill", @"forward.fill" };
    for (int i = 0; i < 3; i++) {
        CGFloat px = cx + (i - 1) * gap;
        _ctrl[i] = CGRectMake(px - cs / 2, cy - cs / 2, cs, cs);
        CGRect r = (i == _pressed) ? CGRectInset(_ctrl[i], cs * 0.14, cs * 0.14) : _ctrl[i];
        SBYDrawSymbol(names[i], (i == _pressed) ? [t.bright colorWithAlphaComponent:0.7] : t.bright, r);
    }
}
@end

#pragma mark - Alarm (full-screen takeover while an alarm is ringing)

@implementation SBYAlarmPageView {
    CGRect _btn[2]; // 0 = Snooze, 1 = Stop
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.minuteTransition = NO; self.liveFPS = 30; }
    return self;
}

- (BOOL)handleTapAt:(CGPoint)p {
    if (CGRectContainsPoint(CGRectInset(_btn[0], -12, -12), p)) { [SBYServices snoozeAlarm]; return YES; }
    if (CGRectContainsPoint(CGRectInset(_btn[1], -12, -12), p)) { [SBYServices stopAlarm]; return YES; }
    return NO;
}

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    NSDictionary *info = [SBYServices ringingAlarm];
    if (!info) return;
    CGFloat w = b.size.width, h = b.size.height;
    CFTimeInterval age = self.pageAge;
    UIColor *orange = t.night ? t.bright : [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];

    // alarm icon that rings: short wobbling bursts, then a pause
    CGFloat is = h * 0.11, left = MAX(46, w * 0.06);
    CGPoint ic = CGPointMake(left + is / 2, h * 0.17);
    CGFloat burst = fmod(age, 1.4);
    CGFloat angle = burst < 0.7 ? sin(burst * 38) * 0.28 * (1 - burst / 0.7) : 0;
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, ic.x, ic.y);
    CGContextRotateCTM(c, angle);
    SBYDrawSymbol(@"alarm.fill", orange, CGRectMake(-is / 2, -is / 2, is, is));
    CGContextRestoreGState(c);
    SBYDrawTextAt(info[@"label"], [UIFont systemFontOfSize:h * 0.075 weight:UIFontWeightSemibold], orange,
                  CGPointMake(left + is + w * 0.02, h * 0.17), NSTextAlignmentLeft, w * 0.6);

    // big time, softly pulsing
    CGFloat pulse = 0.88 + 0.12 * (0.5 + 0.5 * sin(age * 2.6));
    CGContextSaveGState(c);
    CGContextSetAlpha(c, pulse);
    SBYDrawTextAt([SBYServices timeString], SBYExpandedFont(h * 0.42, UIFontWeightSemibold), t.bright,
                  CGPointMake(w / 2, h * 0.5), NSTextAlignmentCenter, [self safeRect].size.width);
    CGContextRestoreGState(c);

    // Snooze (orange) and Stop (grey), like the iOS alarm
    CGFloat bw = w * 0.27, bh = h * 0.17, gap = w * 0.04, by = h * 0.84;
    CGRect snooze = CGRectMake(w / 2 - gap / 2 - bw, by - bh / 2, bw, bh);
    CGRect stop = CGRectMake(w / 2 + gap / 2, by - bh / 2, bw, bh);
    _btn[0] = snooze; _btn[1] = stop;
    UIFont *bf = [UIFont systemFontOfSize:bh * 0.42 weight:UIFontWeightSemibold];
    [orange setFill];
    [[UIBezierPath bezierPathWithRoundedRect:snooze cornerRadius:bh / 2] fill];
    SBYDrawTextAt(@"Snooze", bf, [UIColor blackColor], CGPointMake(CGRectGetMidX(snooze), CGRectGetMidY(snooze)), NSTextAlignmentCenter, 0);
    [(t.night ? t.faint : [UIColor colorWithWhite:0.22 alpha:1]) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:stop cornerRadius:bh / 2] fill];
    SBYDrawTextAt(@"Stop", bf, t.bright, CGPointMake(CGRectGetMidX(stop), CGRectGetMidY(stop)), NSTextAlignmentCenter, 0);
}
@end

#pragma mark - Call (full-screen takeover while a call is ringing / active)

@implementation SBYCallPageView {
    CGRect _btn[2];
    int _kind[2];   // 0 = decline / end, 1 = accept
    int _count;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.minuteTransition = NO; self.liveFPS = 20; }
    return self;
}

- (BOOL)handleTapAt:(CGPoint)p {
    for (int i = 0; i < _count; i++) {
        if (!CGRectContainsPoint(CGRectInset(_btn[i], -14, -14), p)) continue;
        if (_kind[i] == 1) [SBYServices answerCall]; else [SBYServices endCall];
        return YES;
    }
    return NO;
}

- (void)drawContent:(CGContextRef)c bounds:(CGRect)b {
    SBYTheme *t = self.theme;
    NSDictionary *info = [SBYServices callInfo];
    if (!info) return;
    CGFloat w = b.size.width, h = b.size.height;
    NSString *state = info[@"state"];
    NSString *name = info[@"name"] ?: @"Unknown";
    BOOL incoming = [state isEqualToString:@"incoming"];

    // avatar
    CGFloat d = h * 0.5, left = MAX(46, w * 0.06);
    CGPoint ac = CGPointMake(left + d / 2, h * 0.5);
    [[t.faint colorWithAlphaComponent:0.6] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(ac.x - d / 2, ac.y - d / 2, d, d)] fill];
    NSMutableString *initials = [NSMutableString string];
    for (NSString *wd in [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (wd.length && [[NSCharacterSet letterCharacterSet] characterIsMember:[wd characterAtIndex:0]] && initials.length < 2)
            [initials appendString:[[wd substringToIndex:1] uppercaseString]];
    }
    if (initials.length) SBYDrawTextAt(initials, SBYRoundedFont(d * 0.38, UIFontWeightSemibold), t.bright, ac, NSTextAlignmentCenter, 0);
    else SBYDrawSymbol(@"person.fill", t.primary, CGRectMake(ac.x - d * 0.28, ac.y - d * 0.28, d * 0.56, d * 0.56));

    // name + status
    CGFloat x0 = left + d + w * 0.05, tw = w - x0 - 46;
    SBYDrawTextAt(name, [UIFont systemFontOfSize:h * 0.1 weight:UIFontWeightBold], t.bright, CGPointMake(x0, h * 0.3), NSTextAlignmentLeft, tw);
    NSString *line;
    if ([state isEqualToString:@"connected"]) {
        NSDate *since = info[@"since"];
        long sec = since ? lround([[NSDate date] timeIntervalSinceDate:since]) : 0;
        line = sec >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", sec / 3600, (sec % 3600) / 60, sec % 60]
                           : [NSString stringWithFormat:@"%ld:%02ld", sec / 60, sec % 60];
    } else line = incoming ? @"Incoming call…" : @"Calling…";
    SBYDrawTextAt(line, [UIFont monospacedDigitSystemFontOfSize:h * 0.07 weight:UIFontWeightMedium], t.primary, CGPointMake(x0, h * 0.43), NSTextAlignmentLeft, tw);
    NSString *number = info[@"number"];
    if (number.length && ![number isEqualToString:name])
        SBYDrawTextAt(number, [UIFont systemFontOfSize:h * 0.052 weight:UIFontWeightRegular], t.dim, CGPointMake(x0, h * 0.53), NSTextAlignmentLeft, tw);

    // buttons
    CGFloat bd = h * 0.2, by = h * 0.78;
    UIColor *red = t.night ? SBYColorScaled(t.bright, 0.7) : [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1];
    UIColor *green = t.night ? t.bright : [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1];
    UIFont *lf = [UIFont systemFontOfSize:h * 0.048 weight:UIFontWeightMedium];
    _count = incoming ? 2 : 1;
    for (int i = 0; i < _count; i++) {
        BOOL accept = incoming && i == 1;
        CGFloat bx = x0 + bd / 2 + i * (bd + w * 0.06);
        _kind[i] = accept ? 1 : 0;
        _btn[i] = CGRectMake(bx - bd / 2, by - bd / 2, bd, bd);
        UIColor *col = accept ? green : red;
        if (accept) { // gentle pulse so the accept button draws the eye
            CGFloat ph = fmod(self.pageAge * 0.9, 1.0);
            CGFloat rr = bd / 2 + ph * bd * 0.35;
            [[col colorWithAlphaComponent:0.35 * (1 - ph)] setStroke];
            UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(bx - rr, by - rr, rr * 2, rr * 2)];
            ring.lineWidth = 3;
            [ring stroke];
        }
        [col setFill];
        [[UIBezierPath bezierPathWithOvalInRect:_btn[i]] fill];
        SBYDrawSymbol(accept ? @"phone.fill" : @"phone.down.fill", t.night ? [UIColor blackColor] : [UIColor whiteColor],
                      CGRectMake(bx - bd * 0.22, by - bd * 0.22, bd * 0.44, bd * 0.44));
        SBYDrawTextAt(accept ? @"Accept" : (incoming ? @"Decline" : @"End"), lf, t.primary, CGPointMake(bx, by + bd / 2 + h * 0.06), NSTextAlignmentCenter, 0);
    }
}
@end

#pragma mark - Timer (Live Activity style takeover)

@implementation SBYTimerPageView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.minuteTransition = NO; self.liveFPS = 15; }
    return self;
}
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
