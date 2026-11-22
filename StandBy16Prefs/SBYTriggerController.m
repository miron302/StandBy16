// "StandBy16 Trigger Methods" settings pane.
// Every change goes through a warning popup: Continue applies it, Cancel puts that setting back to its default.
#import <UIKit/UIKit.h>

// Minimal declarations of the private Preferences classes (resolved at load time from Settings).
@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSInteger)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (void)setButtonAction:(SEL)action;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static NSString *const kDomain = @"com.miron302.standby16";
enum { kCellLinkList = 2, kCellButton = 13 };

@interface SBYTriggerController : PSListController
- (void)setPreferenceValueDirect:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation SBYTriggerController

#pragma mark - Specifiers

- (PSSpecifier *)methodNamed:(NSString *)name key:(NSString *)key titles:(NSArray *)titles {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:NSClassFromString(@"PSListItemsController")
                                                      cell:kCellLinkList edit:nil];
    NSMutableArray *values = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) [values addObject:@(i)];
    [s setProperty:kDomain forKey:@"defaults"];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@0 forKey:@"default"];   // option 0 is always the stable default
    [s setProperty:name forKey:@"label"];
    [s setValues:values titles:titles];
    return s;
}

- (NSArray *)specifiers {
    NSArray *s = [self valueForKey:@"_specifiers"];
    if (!s) {
        s = [self buildSpecifiers];
        [self setValue:s forKey:@"_specifiers"];
    }
    return s;
}

- (NSArray *)buildSpecifiers {
    NSMutableArray *a = [NSMutableArray array];
    PSSpecifier *warn = [PSSpecifier groupSpecifierWithName:@"Warning"];
    [warn setProperty:@"These options change how StandBy16 detects the trigger sequence (locked + charging + sideways). Changing them is NOT recommended. The first option in every list is the default and the most stable. Every change asks for confirmation." forKey:@"footerText"];
    [a addObject:warn];

    [a addObject:[self methodNamed:@"Orientation detection" key:@"orientationMethod" titles:@[
        @"Accelerometer (default)", @"System orientation", @"Either one", @"Ignore (always sideways)"]]];
    [a addObject:[self methodNamed:@"Orientation direction" key:@"orientationFlip" titles:@[
        @"Normal (default)", @"Flipped 180°"]]];
    [a addObject:[self methodNamed:@"Lock detection" key:@"lockMethod" titles:@[
        @"Lock screen manager (default)", @"Lock-state notification", @"Either one"]]];
    [a addObject:[self methodNamed:@"Screen state" key:@"screenMethod" titles:@[
        @"Backlight controller (default)", @"Blank-screen notification", @"Ignore screen state"]]];
    [a addObject:[self methodNamed:@"Settle delay" key:@"stillnessMethod" titles:@[
        @"Wait until phone is still (default)", @"Off (show immediately)"]]];
    [a addObject:[self methodNamed:@"Overlay method" key:@"overlayMethod" titles:@[
        @"Inside the lock screen (default)", @"Separate window"]]];

    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@""];
    [a addObject:g];
    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"Reset all to defaults" target:self set:nil get:nil
                                                        detail:nil cell:kCellButton edit:nil];
    [reset setButtonAction:@selector(resetAll)];
    [a addObject:reset];

    return a;
}

#pragma mark - Warning popup

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

    // Present from the navigation controller so it works even while the option list is being popped.
    UIViewController *host = self.navigationController ?: self;
    while (host.presentedViewController) host = host.presentedViewController;
    [host presentViewController:ac animated:YES completion:nil];
}

// The real write (PSListController's own implementation), bypassing the popup.
- (void)setPreferenceValueDirect:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

#pragma mark - Reset

- (void)resetAll {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    for (NSString *k in @[@"orientationMethod", @"lockMethod", @"screenMethod", @"stillnessMethod", @"overlayMethod", @"orientationFlip"])
        [d setInteger:0 forKey:k];
    [d synchronize];
    [self reloadSpecifiers];
}

@end
