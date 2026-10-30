#import "SBYController.h"
#import "SBYPages.h"
#import "SBYServices.h"
#import "SBYTheme.h"
#import <notify.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreImage/CoreImage.h>

@interface UIWindow (SBYPrivate)
- (void)_setSecure:(BOOL)secure;
@end

// IOKit isn't in the public iOS SDK, so look the power-assertion calls up at runtime.
static void SBYHoldAwake(BOOL on, uint32_t *idp) {
    static void *io;
    static int (*create)(CFStringRef, uint32_t, CFStringRef, uint32_t *);
    static int (*release)(uint32_t);
    if (!io) {
        io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (io) {
            create = dlsym(io, "IOPMAssertionCreateWithName");
            release = dlsym(io, "IOPMAssertionRelease");
        }
    }
    if (on && create && *idp == 0) {
        create(CFSTR("PreventUserIdleDisplaySleep"), 255, CFSTR("StandBy16"), idp);
    } else if (!on && release && *idp) {
        release(*idp);
        *idp = 0;
    }
}

static UIImage *SBYMonoRed(UIImage *img) {
    CIImage *ci = [[CIImage alloc] initWithImage:img];
    CIFilter *f = [CIFilter filterWithName:@"CIColorMonochrome"];
    [f setValue:ci forKey:kCIInputImageKey];
    [f setValue:[CIColor colorWithRed:1 green:0 blue:0] forKey:kCIInputColorKey];
    [f setValue:@1.0 forKey:kCIInputIntensityKey];
    CIImage *out = f.outputImage;
    if (!out) return img;
    CGImageRef cg = [[CIContext contextWithOptions:nil] createCGImage:out fromRect:ci.extent];
    if (!cg) return img;
    UIImage *r = [UIImage imageWithCGImage:cg scale:img.scale orientation:img.imageOrientation];
    CGImageRelease(cg);
    return r;
}

enum { SBYViewWidgets = 0, SBYViewClock = 1 };

@implementation SBYController {
    UIWindow *_win;
    UIView *_content, *_swatch, *_banner;

    SBYWidgetsPageView *_widgets;
    NSArray<SBYPageView *> *_clockStyles;
    SBYNowPlayingPageView *_nowPlaying;
    SBYTimerPageView *_timerPage;
    SBYPageView *_current;
    NSInteger _viewIndex, _styleIndex;
    BOOL _npDismissed, _timerDismissed;
    NSUInteger _tickCount;

    NSTimer *_tickTimer, *_awakeTimer, *_shiftTimer, *_fadeTimer;
    UIDeviceOrientation _orient;
    BOOL _landscape, _suppressed, _started, _pendingShow;
    CGPoint _shift;

    CGFloat _savedBrightness;
    BOOL _brightnessSaved, _lastNight;
    uint32_t _assertion;
    int _lockToken, _blankToken;

    CTCallCenter *_calls;
    CMMotionManager *_motion;
    double _ax, _ay, _az;
    BOOL _haveAcc;
    NSDate *_lastMotion, *_lastWake;
}

+ (instancetype)shared {
    static SBYController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [SBYController new]; });
    return c;
}

#pragma mark - Lifecycle

- (void)start {
    if (_started) return;
    _started = YES;
    _lastMotion = [NSDate distantPast];
    _lastWake = [NSDate distantPast];

    UIDevice *d = [UIDevice currentDevice];
    d.batteryMonitoringEnabled = YES;
    [d beginGeneratingDeviceOrientationNotifications];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reevaluate) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(tick) name:SBYServicesDidUpdate object:nil];

    __weak typeof(self) weakSelf = self;
    notify_register_dispatch("com.apple.springboard.lockstate", &_lockToken, dispatch_get_main_queue(), ^(int t) { [weakSelf reevaluate]; });
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &_blankToken, dispatch_get_main_queue(), ^(int t) { [weakSelf reevaluate]; });

    // Step aside for calls so the normal incoming-call UI is never covered.
    _calls = [CTCallCenter new];
    _calls.callEventHandler = ^(CTCall *call) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reevaluate]; });
    };

    [SBYServices startMediaObserving];

    _orient = UIDeviceOrientationLandscapeLeft;
    [self orientationChanged];
}

- (void)orientationChanged {
    UIDeviceOrientation o = [UIDevice currentDevice].orientation;
    if (o == UIDeviceOrientationLandscapeLeft || o == UIDeviceOrientationLandscapeRight) {
        _orient = o;
        _landscape = YES;
    } else if (o == UIDeviceOrientationPortrait || o == UIDeviceOrientationPortraitUpsideDown) {
        _landscape = NO;
    } // face up / face down / unknown: keep previous state
    [self reevaluate];
}

#pragma mark - Activation rules (locked + charging + landscape + stationary + screen on)

- (BOOL)isLocked { uint64_t st = 0; notify_get_state(_lockToken, &st); return st != 0; }
- (BOOL)isScreenBlanked { uint64_t st = 0; notify_get_state(_blankToken, &st); return st != 0; }
- (BOOL)callActive { return _calls.currentCalls.count > 0; }

- (void)reevaluate { [self reevaluateAllowingDelay:YES]; }

- (void)reevaluateAllowingDelay:(BOOL)delay {
    BOOL charging = ![SBYPrefs requireCharging] || [SBYServices isCharging];
    BOOL locked = [self isLocked];
    BOOL enabled = [SBYPrefs enabled];
    if (!(charging && locked && _landscape)) _suppressed = NO;

    [self setMotionTracking:(enabled && locked && charging && _landscape)];

    BOOL ok = enabled && locked && ![self isScreenBlanked] && charging && _landscape && !_suppressed && ![self callActive];
    if (ok) {
        if (_win) {
            [self layoutContentAnimated:YES];
            return;
        }
        BOOL settled = [[NSDate date] timeIntervalSinceDate:_lastMotion] > 0.8;
        if (!delay && settled) { [self show]; return; }
        // Real StandBy waits until the phone has settled. Require ~0.8s of steady, still conditions.
        if (!_pendingShow) {
            _pendingShow = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self->_pendingShow = NO;
                [self reevaluateAllowingDelay:NO];
            });
        }
    } else if (_win) {
        [self hide];
    }
}

#pragma mark - Motion (stationary check + motion-to-wake in night mode)

- (void)setMotionTracking:(BOOL)on {
    if (!on) {
        if (_motion.accelerometerActive) [_motion stopAccelerometerUpdates];
        _haveAcc = NO;
        return;
    }
    if (!_motion) { _motion = [CMMotionManager new]; _motion.accelerometerUpdateInterval = 0.1; }
    if (_motion.accelerometerActive || !_motion.accelerometerAvailable) return;
    __weak typeof(self) weakSelf = self;
    [_motion startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMAccelerometerData *data, NSError *err) {
        if (data) [weakSelf accel:data.acceleration];
    }];
}

- (void)accel:(CMAcceleration)a {
    if (_haveAcc) {
        double dv = sqrt(pow(a.x - _ax, 2) + pow(a.y - _ay, 2) + pow(a.z - _az, 2));
        if (dv > 0.05) _lastMotion = [NSDate date];
        if (dv > 0.12) [self maybeWakeForMotion];
    }
    _ax = a.x; _ay = a.y; _az = a.z; _haveAcc = YES;
}

// On non-Always-On iPhones, night-mode StandBy wakes when it senses movement nearby.
- (void)maybeWakeForMotion {
    if (![SBYPrefs boolForKey:@"motionToWake"] || ![self isScreenBlanked] || ![self isLocked] || !_landscape) return;
    if ([SBYPrefs requireCharging] && ![SBYServices isCharging]) return;
    if (![SBYTheme current].night) return;
    if ([[NSDate date] timeIntervalSinceDate:_lastWake] < 3) return;
    _lastWake = [NSDate date];
    Class bl = NSClassFromString(@"SBBacklightController");
    id inst = [bl respondsToSelector:@selector(sharedInstance)] ? [bl performSelector:@selector(sharedInstance)] : nil;
    SEL s = NSSelectorFromString(@"turnOnScreenFullyWithBacklightSource:");
    if ([inst respondsToSelector:s]) ((void (*)(id, SEL, long long))objc_msgSend)(inst, s, 1);
}

#pragma mark - Show / hide

- (void)show {
    // Estimate "dark room" from the system's auto-brightness level, before we touch brightness.
    if (!_brightnessSaved)
        [SBYTheme setAmbientDark:[UIScreen mainScreen].brightness < [SBYPrefs ambientThreshold]];

    CGRect sb = [UIScreen mainScreen].fixedCoordinateSpace.bounds;
    _win = [[UIWindow alloc] initWithFrame:sb];
    _win.windowLevel = [SBYPrefs integerForKey:@"windowLevel"];
    _win.backgroundColor = [UIColor blackColor];
    if ([_win respondsToSelector:@selector(_setSecure:)]) [_win _setSecure:YES];
    _win.rootViewController = [UIViewController new];
    _win.rootViewController.view.backgroundColor = [UIColor blackColor];

    _content = [UIView new];
    _content.backgroundColor = [UIColor blackColor];
    _content.clipsToBounds = YES;
    [_win.rootViewController.view addSubview:_content];
    [_content addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [_content addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
    [_content addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];

    _widgets = [[SBYWidgetsPageView alloc] initWithFrame:CGRectZero];
    _nowPlaying = [[SBYNowPlayingPageView alloc] initWithFrame:CGRectZero];
    _timerPage = [[SBYTimerPageView alloc] initWithFrame:CGRectZero];
    NSMutableArray *styles = [NSMutableArray array];
    for (Class k in SBYClockStyleClasses()) [styles addObject:[[k alloc] initWithFrame:CGRectZero]];
    _clockStyles = styles;
    _npDismissed = _timerDismissed = NO;

    // Reopen on whichever view / style was used last, like StandBy does.
    _viewIndex = [SBYPrefs integerForKey:@"lastView"] == SBYViewWidgets ? SBYViewWidgets : SBYViewClock;
    _styleIndex = MAX(0, MIN((NSInteger)_clockStyles.count - 1, [SBYPrefs integerForKey:@"lastStyle"]));
    _current = [self desiredOverlay] ?: [self baseView];
    _shift = CGPointZero;
    [_content addSubview:_current];

    [self layoutContentAnimated:NO];
    _win.alpha = 0;
    _win.hidden = NO;
    [UIView animateWithDuration:0.6 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ self->_win.alpha = 1; } completion:nil];

    SBYTheme *t = [SBYTheme current];
    _current.theme = t;
    _lastNight = t.night;
    [self applyBrightnessForTheme:t];
    [SBYServices refreshWeatherIfNeeded];
    [SBYServices refreshNowPlaying];

    _tickCount = 0;
    _tickTimer = [NSTimer timerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    _shiftTimer = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(pixelShift) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_tickTimer forMode:NSRunLoopCommonModes];
    [[NSRunLoop mainRunLoop] addTimer:_shiftTimer forMode:NSRunLoopCommonModes];
    if ([SBYPrefs keepAwake]) {
        _awakeTimer = [NSTimer timerWithTimeInterval:15 target:self selector:@selector(keepAwake) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_awakeTimer forMode:NSRunLoopCommonModes];
        [self keepAwake];
    }
}

- (void)hide {
    [_tickTimer invalidate]; [_awakeTimer invalidate]; [_shiftTimer invalidate];
    _tickTimer = _awakeTimer = _shiftTimer = nil;
    SBYHoldAwake(NO, &_assertion);
    [_fadeTimer invalidate]; _fadeTimer = nil;
    if (_brightnessSaved) {
        [UIScreen mainScreen].brightness = _savedBrightness;
        _brightnessSaved = NO;
    }
    UIWindow *gone = _win;
    [UIView animateWithDuration:0.25 animations:^{ gone.alpha = 0; } completion:^(BOOL f) { gone.hidden = YES; }];
    _win = nil; _content = nil; _swatch = nil; _banner = nil;
    _widgets = nil; _clockStyles = nil; _nowPlaying = nil; _timerPage = nil; _current = nil;
}

- (SBYPageView *)baseView {
    return _viewIndex == SBYViewWidgets ? (SBYPageView *)_widgets : _clockStyles[_styleIndex];
}

// Timers and Now Playing take over the screen automatically (swipe to dismiss), like StandBy.
- (SBYPageView *)desiredOverlay {
    NSTimeInterval rem = 0, tot = 0;
    BOOL timerOn = [SBYPrefs boolForKey:@"timerActivity"] && [SBYServices timerRemaining:&rem total:&tot];
    if (!timerOn) _timerDismissed = NO;
    NSDictionary *np = [SBYServices nowPlaying];
    BOOL playing = [SBYPrefs boolForKey:@"nowPlaying"] && np && [np[@"playing"] boolValue];
    if (!playing) _npDismissed = NO;
    if (timerOn && !_timerDismissed) return _timerPage;
    if (playing && !_npDismissed) return _nowPlaying;
    return nil;
}

#pragma mark - Layout (the lock screen is portrait-only, so rotate our content by hand)

- (void)layoutContentAnimated:(BOOL)animated {
    if (!_content) return;
    CGRect sb = [UIScreen mainScreen].fixedCoordinateSpace.bounds;
    CGFloat angle = (_orient == UIDeviceOrientationLandscapeLeft) ? M_PI_2 : -M_PI_2;
    void (^apply)(void) = ^{
        self->_content.transform = CGAffineTransformIdentity;
        self->_content.bounds = CGRectMake(0, 0, sb.size.height, sb.size.width);
        self->_content.center = CGPointMake(sb.size.width / 2, sb.size.height / 2);
        self->_content.transform = CGAffineTransformMakeRotation(angle);
        self->_current.frame = CGRectOffset(self->_content.bounds, self->_shift.x, self->_shift.y);
    };
    if (animated) [UIView animateWithDuration:0.3 animations:apply];
    else apply();
}

#pragma mark - Timers

- (void)tick {
    if (!_current) return;
    if ([self callActive]) { [self reevaluate]; return; }
    _tickCount++;
    if (_tickCount % 8 == 0) [SBYServices refreshNowPlaying];

    SBYPageView *want = [self desiredOverlay] ?: [self baseView];
    if (want != _current) [self swapTo:want dx:0 dy:0];

    SBYTheme *t = [SBYTheme current];
    if (t.night != _lastNight) {
        _lastNight = t.night;
        [self applyBrightnessForTheme:t];
    }
    _current.theme = t;
    [_current tick];
}

// Night mode dims hard, like StandBy. (We can only sample ambient light before we dim,
// so the dark/light decision is refreshed each time StandBy appears.)
- (void)applyBrightnessForTheme:(SBYTheme *)t {
    CGFloat nb = [SBYPrefs nightBrightness];
    if (t.night && nb > 0) {
        if (!_brightnessSaved) {
            _savedBrightness = [UIScreen mainScreen].brightness;
            _brightnessSaved = YES;
        }
        [self fadeBrightnessTo:nb];
    } else if (_brightnessSaved) {
        _brightnessSaved = NO;
        [self fadeBrightnessTo:_savedBrightness];
    }
}

// Ease brightness over ~0.6s instead of snapping, the way iOS does.
- (void)fadeBrightnessTo:(CGFloat)target {
    [_fadeTimer invalidate];
    CGFloat from = [UIScreen mainScreen].brightness;
    __block int step = 0;
    const int N = 12;
    _fadeTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *tm) {
        step++;
        CGFloat k = MIN(1.0, step / (CGFloat)N);
        k = k * k * (3 - 2 * k); // smoothstep
        [UIScreen mainScreen].brightness = from + (target - from) * k;
        if (step >= N) [tm invalidate];
    }];
}

// Only when keepAwake=true: best-effort stop of auto-lock (selector names differ between iOS versions).
- (void)keepAwake {
    SBYHoldAwake(YES, &_assertion);
    Class bl = NSClassFromString(@"SBBacklightController");
    id inst = [bl respondsToSelector:@selector(sharedInstance)] ? [bl performSelector:@selector(sharedInstance)] : nil;
    SEL sels[] = { NSSelectorFromString(@"resetLockScreenIdleTimer"), NSSelectorFromString(@"resetIdleTimer") };
    for (int i = 0; i < 2; i++) {
        if ([inst respondsToSelector:sels[i]]) { [inst performSelector:sels[i]]; break; }
    }
}

// OLED (iPhone X) burn-in protection: nudge everything a few points every minute.
- (void)pixelShift {
    _shift = CGPointMake((CGFloat)((int)arc4random_uniform(17) - 8), (CGFloat)((int)arc4random_uniform(17) - 8));
    [UIView animateWithDuration:1.0 animations:^{
        self->_current.frame = CGRectOffset(self->_content.bounds, self->_shift.x, self->_shift.y);
    }];
}

#pragma mark - Gestures (all coordinates are in the rotated content's own space)
//  swipe left/right        -> Widgets <-> Clock (or dismiss a Now Playing / Timer takeover)
//  swipe up/down           -> Clock: change style / Widgets: scroll the stack you touched
//  swipe up from bottom    -> leave StandBy, back to the normal lock screen
//  tap                     -> Now Playing controls, stack editor
//  long press              -> Clock: cycle colour / Widgets: edit the stack

- (void)pan:(UIPanGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded || !_current) return;
    CGPoint tr = [g translationInView:_content];
    CGPoint loc = [g locationInView:_content];
    CGPoint vel = [g velocityInView:_content];
    BOOL fastX = fabs(vel.x) > 700 && fabs(tr.x) > 25, fastY = fabs(vel.y) > 700 && fabs(tr.y) > 25;
    CGPoint start = CGPointMake(loc.x - tr.x, loc.y - tr.y);

    if (start.y > _content.bounds.size.height - 70 && (tr.y < -50 || fastY) && tr.y < 0 && fabs(tr.y) > fabs(tr.x)) {
        _suppressed = YES;
        [self hide];
        return;
    }
    if (_current == _nowPlaying || _current == _timerPage) {
        if (hypot(tr.x, tr.y) > 60 || fastX || fastY) {
            if (_current == _nowPlaying) _npDismissed = YES; else _timerDismissed = YES;
            [self swapTo:[self baseView] dx:(tr.x < 0 ? 1 : -1) dy:0];
        }
        return;
    }
    if ([_current isEditing]) return;

    if (fabs(tr.x) > fabs(tr.y) && (fabs(tr.x) > 60 || fastX)) {
        NSInteger target = _viewIndex + (tr.x < 0 ? 1 : -1);
        if (target >= SBYViewWidgets && target <= SBYViewClock && target != _viewIndex) {
            _viewIndex = target;
            [SBYPrefs setInteger:_viewIndex forKey:@"lastView"];
            [self swapTo:[self baseView] dx:(tr.x < 0 ? 1 : -1) dy:0];
        }
    } else if (fabs(tr.y) > 60 || fastY) {
        int d = tr.y < 0 ? 1 : -1; // swipe up = next
        if (_viewIndex == SBYViewClock) {
            NSInteger ni = _styleIndex + d;
            if (ni >= 0 && ni < (NSInteger)_clockStyles.count) {
                _styleIndex = ni;
                [SBYPrefs setInteger:ni forKey:@"lastStyle"];
                [self swapTo:_clockStyles[ni] dx:0 dy:d];
            }
        } else {
            [_widgets scrollStack:(start.x < _content.bounds.size.width / 2 ? 0 : 1) by:d];
        }
    }
}

- (void)tap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded || !_current) return;
    CGPoint p = [_content convertPoint:[g locationInView:_content] toView:_current];
    [_current handleTapAt:p];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || !_current) return;
    if (_current == _widgets) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        [_widgets handleLongPressAt:[_content convertPoint:[g locationInView:_content] toView:_current]];
        return;
    }
    if (_current == _nowPlaying || _current == _timerPage) return;
    if ([SBYTheme current].night) return; // night mode ignores colour choices
    NSInteger i = ([SBYPrefs integerForKey:@"tintIndex"] + 1) % [SBYTheme tintCount];
    [SBYPrefs setInteger:i forKey:@"tintIndex"];
    UIColor *col = [SBYTheme tintColorForIndex:i] ?: [UIColor whiteColor];

    [_swatch removeFromSuperview];
    CGFloat d = 34;
    _swatch = [[UIView alloc] initWithFrame:CGRectMake(_content.bounds.size.width / 2 - d / 2, _content.bounds.size.height - d - 18, d, d)];
    _swatch.backgroundColor = col;
    _swatch.layer.cornerRadius = d / 2;
    _swatch.layer.borderWidth = 3;
    _swatch.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    [_content addSubview:_swatch];
    [[UIImpactFeedbackGenerator new] impactOccurred];
    _swatch.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:0 animations:^{ self->_swatch.transform = CGAffineTransformIdentity; } completion:nil];
    UIView *sw = _swatch;
    [UIView animateWithDuration:0.4 delay:1.2 options:0 animations:^{ sw.alpha = 0; } completion:^(BOOL f) { [sw removeFromSuperview]; }];
    [self tick];
}

- (void)swapTo:(SBYPageView *)next dx:(int)dx dy:(int)dy {
    SBYPageView *old = _current;
    if (!next || next == old) return;
    if (dx || dy) [[UISelectionFeedbackGenerator new] selectionChanged];
    next.theme = [SBYTheme current];
    next.frame = CGRectOffset(_content.bounds, _shift.x, _shift.y);
    next.alpha = 0;
    next.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(dx * 60, dy * 60), 0.96, 0.96);
    if (_banner.superview == _content) [_content insertSubview:next belowSubview:_banner];
    else if (_swatch.superview == _content) [_content insertSubview:next belowSubview:_swatch];
    else [_content addSubview:next];
    _current = next;
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        next.alpha = 1;
        next.transform = CGAffineTransformIdentity;
        old.alpha = 0;
        old.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(-dx * 60, -dy * 60), 0.96, 0.96);
    } completion:^(BOOL finished) {
        [old removeFromSuperview];
        old.alpha = 1;
        old.transform = CGAffineTransformIdentity;
    }];
}

#pragma mark - Notifications (enlarged banner)

- (void)showBannerApp:(NSString *)app title:(NSString *)title message:(NSString *)message sectionID:(NSString *)sid {
    if (!_win || !_content || ![SBYPrefs boolForKey:@"notifications"]) return;
    if (!title.length && !message.length) return;
    SBYTheme *t = [SBYTheme current];
    CGFloat W = _content.bounds.size.width, H = _content.bounds.size.height;
    CGFloat bw = W * 0.62, bh = H * 0.3, pad = 18;

    [_banner removeFromSuperview];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake((W - bw) / 2, -bh, bw, bh)];
    v.backgroundColor = t.night ? [UIColor colorWithRed:0.16 green:0 blue:0 alpha:1] : [UIColor colorWithWhite:0.16 alpha:1];
    v.layer.cornerRadius = 28;

    CGFloat icon = bh * 0.52;
    UIImage *img = nil;
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (sid.length && [UIImage respondsToSelector:sel])
        img = ((UIImage * (*)(Class, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], sel, sid, 2, [UIScreen mainScreen].scale);
    CGFloat tx = pad;
    if (img) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:t.night ? SBYMonoRed(img) : img];
        iv.frame = CGRectMake(pad, (bh - icon) / 2, icon, icon);
        iv.layer.cornerRadius = icon * 0.22;
        iv.clipsToBounds = YES;
        [v addSubview:iv];
        tx = pad + icon + 14;
    }
    CGFloat tw = bw - tx - pad;
    UILabel *a = [[UILabel alloc] initWithFrame:CGRectMake(tx, bh * 0.14, tw, 18)];
    a.text = [app uppercaseString];
    a.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    a.textColor = t.dim;
    UILabel *ti = [[UILabel alloc] initWithFrame:CGRectMake(tx, bh * 0.14 + 22, tw, 28)];
    ti.text = title;
    ti.font = [UIFont systemFontOfSize:23 weight:UIFontWeightSemibold];
    ti.textColor = t.bright;
    UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(tx, bh * 0.14 + 52, tw, bh - (bh * 0.14 + 52) - 12)];
    m.text = message;
    m.numberOfLines = 2;
    m.font = [UIFont systemFontOfSize:19 weight:UIFontWeightRegular];
    m.textColor = t.primary;
    for (UIView *s in @[a, ti, m]) [v addSubview:s];

    [_content addSubview:v];
    _banner = v;
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0 options:0
                     animations:^{ v.frame = CGRectOffset(v.frame, 0, bh + H * 0.06); } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.35 animations:^{ v.frame = CGRectOffset(v.frame, 0, -(bh + H * 0.06)); }
                         completion:^(BOOL f) { [v removeFromSuperview]; }];
    });
}

@end
