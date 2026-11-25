// StandBy16 Preview: runs the exact same StandBy pages as a normal landscape app,
// so you can check the UI independently of the lock-screen trigger.
#import <UIKit/UIKit.h>
#import "SBYPages.h"
#import "SBYServices.h"
#import "SBYTheme.h"

enum { PVWidgets = 0, PVClock = 1 };

@interface PreviewViewController : UIViewController @end

@implementation PreviewViewController {
    SBYWidgetsPageView *_widgets;
    NSArray<SBYPageView *> *_styles;
    SBYPageView *_current;
    NSInteger _view, _style;
    NSTimer *_timer;
    BOOL _night;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _widgets = [[SBYWidgetsPageView alloc] initWithFrame:CGRectZero];
    NSMutableArray *styles = [NSMutableArray array];
    for (Class k in SBYClockStyleClasses()) [styles addObject:[[k alloc] initWithFrame:CGRectZero]];
    _styles = styles;
    _view = PVClock;
    _style = 0;
    _current = _styles[0];
    [self.view addSubview:_current];

    [self.view addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)]];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:dbl];
    [self.view addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _current.frame = self.view.bounds;
}

- (void)tick {
    [SBYTheme setAmbientDark:_night];
    _current.theme = [SBYTheme current];
    [_current tick];
}

- (SBYPageView *)base { return _view == PVWidgets ? (SBYPageView *)_widgets : _styles[_style]; }

- (void)swapTo:(SBYPageView *)next dx:(int)dx dy:(int)dy {
    SBYPageView *old = _current;
    if (next == old) return;
    next.theme = [SBYTheme current];
    next.frame = self.view.bounds;
    next.alpha = 0;
    next.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(dx * 60, dy * 110), 0.96, 0.96);
    [self.view addSubview:next];
    _current = next;
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        next.alpha = 1;
        next.transform = CGAffineTransformIdentity;
        old.alpha = 0;
        old.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(-dx * 60, -dy * 110), 0.96, 0.96);
    } completion:^(BOOL f) {
        [old removeFromSuperview];
        old.alpha = 1;
        old.transform = CGAffineTransformIdentity;
    }];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded || [_current isEditing]) return;
    CGPoint tr = [g translationInView:self.view], loc = [g locationInView:self.view], vel = [g velocityInView:self.view];
    BOOL fastX = fabs(vel.x) > 700 && fabs(tr.x) > 25, fastY = fabs(vel.y) > 700 && fabs(tr.y) > 25;
    CGPoint start = CGPointMake(loc.x - tr.x, loc.y - tr.y);
    if (fabs(tr.x) > fabs(tr.y) && (fabs(tr.x) > 60 || fastX)) {
        NSInteger target = _view + (tr.x < 0 ? 1 : -1);
        if (target >= PVWidgets && target <= PVClock && target != _view) {
            _view = target;
            [self swapTo:[self base] dx:(tr.x < 0 ? 1 : -1) dy:0];
        }
    } else if (fabs(tr.y) > 60 || fastY) {
        int d = tr.y < 0 ? 1 : -1;
        if (_view == PVClock) {
            NSInteger ni = _style + d;
            if (ni >= 0 && ni < (NSInteger)_styles.count) {
                _style = ni;
                [self swapTo:_styles[ni] dx:0 dy:d];
            }
        } else {
            [_widgets scrollStack:(start.x < self.view.bounds.size.width / 2 ? 0 : 1) by:d];
        }
    }
}

- (void)tap:(UITapGestureRecognizer *)g {
    [_current handleTapAt:[g locationInView:_current]];
}

// Double tap = toggle red night mode so you can preview it.
- (void)doubleTap:(UITapGestureRecognizer *)g {
    _night = !_night;
    [self tick];
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (_current == _widgets) { [_widgets handleLongPressAt:[g locationInView:_current]]; return; }
    NSInteger i = ([SBYPrefs integerForKey:@"tintIndex"] + 1) % [SBYTheme tintCount];
    [SBYPrefs setInteger:i forKey:@"tintIndex"];
    [self tick];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [PreviewViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
