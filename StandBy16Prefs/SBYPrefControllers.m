// StandBy16 settings: a clean root page, a Colors page and the advanced Trigger Methods page.
#import <UIKit/UIKit.h>
#import <notify.h>

// Minimal declarations of the private Preferences classes (resolved at load time from Settings).
@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (void)setButtonAction:(SEL)action;
@end

@interface PSListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

static NSString *const kDomain = @"com.miron302.standby16";
enum { kCellLink = 1, kCellLinkList = 2, kCellSwitch = 6, kCellEditText = 8, kCellButton = 13 };

static NSUserDefaults *SBYDefaults(void) {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[NSUserDefaults alloc] initWithSuiteName:kDomain]; });
    return d;
}

#pragma mark - Specifier helpers

static PSSpecifier *SBYGroup(NSString *title, NSString *footer) {
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:title ?: @""];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

static PSSpecifier *SBYSpec(id target, NSString *label, Class detail, NSInteger cell, NSString *key, id def) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:target
                                                       set:key ? @selector(setPreferenceValue:specifier:) : (SEL)0
                                                       get:key ? @selector(readPreferenceValue:) : (SEL)0
                                                    detail:detail cell:cell edit:nil];
    if (key) {
        [s setProperty:kDomain forKey:@"defaults"];
        [s setProperty:key forKey:@"key"];
        [s setProperty:label forKey:@"label"];
        if (def) [s setProperty:def forKey:@"default"];
    }
    return s;
}

static PSSpecifier *SBYSwitch(id target, NSString *label, NSString *key, BOOL def) {
    return SBYSpec(target, label, nil, kCellSwitch, key, @(def));
}

static PSSpecifier *SBYList(id target, NSString *label, NSString *key, NSArray *titles, id def) {
    PSSpecifier *s = SBYSpec(target, label, NSClassFromString(@"PSListItemsController"), kCellLinkList, key, def);
    NSMutableArray *values = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) [values addObject:@(i)];
    [s setValues:values titles:titles];
    return s;
}

static PSSpecifier *SBYText(id target, NSString *label, NSString *key, NSString *def) {
    return SBYSpec(target, label, nil, kCellEditText, key, def);
}

static PSSpecifier *SBYLink(id target, NSString *label, Class detail) {
    return SBYSpec(target, label, detail, kCellLink, nil, nil);
}

static PSSpecifier *SBYButton(id target, NSString *label, SEL action) {
    PSSpecifier *s = SBYSpec(target, label, nil, kCellButton, nil, nil);
    [s setButtonAction:action];
    return s;
}

#pragma mark - Colour storage ("RRGGBB" hex strings the tweak reads)

static UIColor *SBYColorFromHex(NSString *hex) {
    if (hex.length != 6) return nil;
    unsigned v = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&v]) return nil;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

static NSString *SBYHexFromColor(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%02X%02X%02X", (int)lround(r * 255), (int)lround(g * 255), (int)lround(b * 255)];
}

#pragma mark - Base

@interface SBYBaseController : PSListController
- (NSArray *)buildSpecifiers;
@end

@implementation SBYBaseController
- (NSArray *)specifiers {
    NSArray *s = [self valueForKey:@"_specifiers"];
    if (!s) {
        s = [self buildSpecifiers];
        [self setValue:s forKey:@"_specifiers"];
    }
    return s;
}
- (NSArray *)buildSpecifiers { return @[]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}
@end

#pragma mark - Colors

@interface SBYColorsController : SBYBaseController <UIColorPickerViewControllerDelegate> @end

@implementation SBYColorsController {
    NSString *_editingKey;
}

- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Colors"; }

- (NSArray *)buildSpecifiers {
    PSSpecifier *normal = SBYButton(self, @"Color", @selector(chooseNormal));
    [normal setProperty:@"normalColorHex" forKey:@"colorKey"];
    PSSpecifier *night = SBYButton(self, @"Color", @selector(chooseNight));
    [night setProperty:@"nightColorHex" forKey:@"colorKey"];
    return @[
        SBYGroup(@"Normal mode", @"The color of the clock and widgets in normal light. Leave it on default for each style's own look."),
        normal,
        SBYButton(self, @"Use default", @selector(resetNormal)),
        SBYGroup(@"Night mode", @"The color used in a dark room. Red by default, which is easiest on the eyes."),
        night,
        SBYButton(self, @"Use default", @selector(resetNight)),
    ];
}

// Colour swatch on the right of each "Color" row
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
    NSString *key = [[self specifierAtIndexPath:ip] propertyForKey:@"colorKey"];
    if (key) {
        UIColor *c = [self currentColorForKey:key];
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        dot.backgroundColor = c;
        dot.layer.cornerRadius = 15;
        dot.layer.borderWidth = 1;
        dot.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.5].CGColor;
        cell.accessoryView = dot;
    }
    return cell;
}

- (UIColor *)currentColorForKey:(NSString *)key {
    UIColor *c = SBYColorFromHex([SBYDefaults() stringForKey:key]);
    if (c) return c;
    return [key isEqualToString:@"nightColorHex"] ? [UIColor colorWithRed:1 green:0 blue:0 alpha:1] : [UIColor whiteColor];
}

- (void)pickForKey:(NSString *)key title:(NSString *)title {
    _editingKey = key;
    UIColorPickerViewController *pk = [UIColorPickerViewController new];
    pk.supportsAlpha = NO;
    pk.selectedColor = [self currentColorForKey:key];
    pk.delegate = self;
    pk.title = title;
    [self presentViewController:pk animated:YES completion:nil];
}
- (void)chooseNormal { [self pickForKey:@"normalColorHex" title:@"Normal mode color"]; }
- (void)chooseNight { [self pickForKey:@"nightColorHex" title:@"Night mode color"]; }

- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (!_editingKey) return;
    [SBYDefaults() setObject:SBYHexFromColor(color) forKey:_editingKey];
    [SBYDefaults() synchronize];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc { [self reloadSpecifiers]; }

- (void)resetKey:(NSString *)key {
    [SBYDefaults() removeObjectForKey:key];
    [SBYDefaults() synchronize];
    [self reloadSpecifiers];
}
- (void)resetNormal { [self resetKey:@"normalColorHex"]; }
- (void)resetNight { [self resetKey:@"nightColorHex"]; }
@end

#pragma mark - Trigger Methods (advanced, every change asks first)

@interface SBYTriggerController : SBYBaseController
- (void)setPreferenceValueDirect:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation SBYTriggerController

- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Trigger Methods"; }

- (NSArray *)buildSpecifiers {
    return @[
        SBYGroup(@"Warning", @"These options change how StandBy16 detects the trigger (locked + charging + sideways). Changing them is NOT recommended. The first option in every list is the default and the most stable."),
        SBYList(self, @"Orientation detection", @"orientationMethod", @[@"Accelerometer (default)", @"System orientation", @"Either one", @"Ignore (always sideways)"], @0),
        SBYList(self, @"Orientation direction", @"orientationFlip", @[@"Normal (default)", @"Flipped 180°"], @0),
        SBYList(self, @"Lock detection", @"lockMethod", @[@"Lock screen manager (default)", @"Lock-state notification", @"Either one"], @0),
        SBYList(self, @"Screen state", @"screenMethod", @[@"Backlight controller (default)", @"Blank-screen notification", @"Ignore screen state"], @0),
        SBYList(self, @"Settle delay", @"stillnessMethod", @[@"Quick, 0.25s (default)", @"Off (show immediately)", @"Relaxed, 0.8s"], @0),
        SBYList(self, @"Overlay method", @"overlayMethod", @[@"Inside the lock screen (default)", @"Separate window"], @0),
        SBYGroup(@"Diagnostics", @"Test mode shows StandBy whenever the phone is locked, ignoring charging and rotation. The log is /var/mobile/Library/Logs/StandBy16.log"),
        SBYSwitch(self, @"Test mode", @"forceShow", NO),
        SBYSwitch(self, @"Debug log", @"debug", YES),
        SBYGroup(@"", nil),
        SBYButton(self, @"Reset all to defaults", @selector(resetAll)),
    ];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    id current = [self readPreferenceValue:specifier];
    if ([current isEqual:value]) return;

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"WARNING!"
                         message:@"Changing these methods is NOT recommended!! If you want maximum stability, keep the default one!! Change this at your own risk."
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Continue changing" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *act) {
        [weakSelf setPreferenceValueDirect:value specifier:specifier];
        [weakSelf reloadSpecifiers];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *act) {
        [weakSelf setPreferenceValueDirect:[specifier propertyForKey:@"default"] specifier:specifier];
        [weakSelf reloadSpecifiers];
    }]];
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:ac animated:YES completion:nil];
}

// The real write (PSListController's own implementation), bypassing the popup.
- (void)setPreferenceValueDirect:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
}

- (void)resetAll {
    for (NSString *k in @[@"orientationMethod", @"orientationFlip", @"lockMethod", @"screenMethod", @"stillnessMethod", @"overlayMethod", @"forceShow", @"debug"])
        [SBYDefaults() removeObjectForKey:k];
    [SBYDefaults() synchronize];
    [self reloadSpecifiers];
}
@end

#pragma mark - Root

@interface SBYRootController : SBYBaseController @end

@implementation SBYRootController

- (void)viewDidLoad { [super viewDidLoad]; self.title = @"StandBy16"; }

- (NSArray *)buildSpecifiers {
    NSString *version = [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    return @[
        SBYGroup(@"", @"Lock your phone, plug it in and turn it sideways."),
        SBYSwitch(self, @"StandBy", @"enabled", YES),

        SBYGroup(@"Look", nil),
        SBYLink(self, @"Colors", [SBYColorsController class]),
        SBYList(self, @"Night mode", @"nightMode", @[@"Automatic", @"Always", @"Never"], @0),

        SBYGroup(@"Display", @"Keeps StandBy on and dims it when you are not touching it. To turn the screen off, swipe up from the bottom edge to leave StandBy first, then press the side button."),
        SBYSwitch(self, @"Always On", @"alwaysOn", NO),

        SBYGroup(@"Show", nil),
        SBYSwitch(self, @"Now Playing", @"nowPlaying", YES),
        SBYSwitch(self, @"Timers", @"timerActivity", YES),
        SBYSwitch(self, @"Notifications", @"notifications", YES),
        SBYSwitch(self, @"Calls", @"callsView", YES),
        SBYSwitch(self, @"Alarms", @"alarmView", YES),
        SBYSwitch(self, @"Smart Rotate", @"smartRotate", YES),

        SBYGroup(@"Weather", @"Used by the weather widget and the world clock."),
        SBYText(self, @"City", @"cityName", @"London"),
        SBYText(self, @"Latitude", @"latitude", @"51.5072"),
        SBYText(self, @"Longitude", @"longitude", @"-0.1276"),
        SBYSwitch(self, @"Fahrenheit", @"fahrenheit", NO),

        SBYGroup(@"Preview", @"Try StandBy without plugging in or turning the phone."),
        SBYButton(self, @"Preview StandBy", @selector(previewNow)),
        SBYButton(self, @"Open Preview App", @selector(openPreviewApp)),

        SBYGroup(@"", [NSString stringWithFormat:@"StandBy16 %@", version]),
        SBYLink(self, @"Advanced", [SBYTriggerController class]),
    ];
}

- (void)previewNow { notify_post("com.miron302.standby16/preview"); }
- (void)openPreviewApp { notify_post("com.miron302.standby16/openapp"); }
@end
