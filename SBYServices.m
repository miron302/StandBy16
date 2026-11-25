#import "SBYServices.h"
#import "SBYTheme.h"
#import <dlfcn.h>

NSString *const SBYServicesDidUpdate = @"SBYServicesDidUpdate";

@implementation SBYServices

+ (BOOL)is24h {
    NSString *f = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
    return ![f containsString:@"a"];
}

+ (NSString *)format:(NSString *)fmt date:(NSDate *)d {
    static NSDateFormatter *df;
    if (!df) df = [NSDateFormatter new];
    df.locale = [NSLocale currentLocale];
    df.dateFormat = fmt;
    return [df stringFromDate:d];
}

+ (NSString *)clockFormat { return [self is24h] ? @"HH:mm" : @"h:mm"; }
+ (NSString *)timeString { return [self format:[self clockFormat] date:[NSDate date]]; }
+ (NSString *)upperDateString { return [[self format:@"EEE d" date:[NSDate date]] uppercaseString]; }
+ (NSString *)weekdayShort { return [self format:@"EEE" date:[NSDate date]]; }
+ (NSString *)monthShort { return [self format:@"MMM" date:[NSDate date]]; }
+ (NSString *)dayNumber { return [self format:@"d" date:[NSDate date]]; }

+ (NSDateComponents *)nowComponents {
    return [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond)
                                           fromDate:[NSDate date]];
}

#pragma mark - Alarm (MobileTimer, loaded at runtime so nothing to link)

static id SBYAlarmManagerInstance(void) {
    static id mgr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer", RTLD_NOW);
        Class c = NSClassFromString(@"MTAlarmManager");
        if (c) mgr = [[c alloc] init];
    });
    return mgr;
}

// The next alarm object and its fire date (only if it is within the next 24 hours).
static id SBYNextAlarmObject(NSDate **fireOut) {
    id mgr = SBYAlarmManagerInstance();
    if (!mgr) return nil;
    @try {
        id alarm = [mgr respondsToSelector:@selector(nextAlarmSync)] ? [mgr performSelector:@selector(nextAlarmSync)] : nil;
        if (!alarm || ![alarm respondsToSelector:@selector(nextFireDate)]) return nil;
        NSDate *fire = [alarm performSelector:@selector(nextFireDate)];
        if (![fire isKindOfClass:[NSDate class]]) return nil;
        NSTimeInterval dt = [fire timeIntervalSinceNow];
        if (dt < 0 || dt > 24 * 3600) return nil;
        if (fireOut) *fireOut = fire;
        return alarm;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

+ (NSDate *)nextAlarmDate {
    NSDate *fire = nil;
    return SBYNextAlarmObject(&fire) ? fire : nil;
}

+ (NSString *)alarmString {
    NSDate *d = [self nextAlarmDate];
    return d ? [self format:[self clockFormat] date:d] : nil;
}

#pragma mark - Timer (MTTimerManager, runtime lookup; nothing shows if the API differs)

+ (BOOL)timerRemaining:(NSTimeInterval *)remaining total:(NSTimeInterval *)total {
    static id mgr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer", RTLD_NOW);
        Class c = NSClassFromString(@"MTTimerManager");
        if (c) mgr = [[c alloc] init];
    });
    if (!mgr) return NO;
    @try {
        id timer = nil;
        if ([mgr respondsToSelector:@selector(currentTimerSync)]) timer = [mgr performSelector:@selector(currentTimerSync)];
        if (!timer) return NO;
        NSDate *fire = [timer valueForKey:@"fireDate"];
        if (![fire isKindOfClass:[NSDate class]]) return NO;
        NSTimeInterval rem = [fire timeIntervalSinceNow];
        if (rem <= 0) return NO;
        NSNumber *dur = nil;
        @try { dur = [timer valueForKey:@"duration"]; } @catch (__unused NSException *e) {}
        if (remaining) *remaining = rem;
        if (total) *total = [dur isKindOfClass:[NSNumber class]] && [dur doubleValue] > 0 ? [dur doubleValue] : rem;
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

#pragma mark - Now Playing (MediaRemote)

typedef void (*SBYMRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*SBYMRGetPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*SBYMRRegister)(dispatch_queue_t);
typedef Boolean (*SBYMRSend)(int, id);
static SBYMRGetInfo pGetInfo;
static SBYMRGetPlaying pGetPlaying;
static SBYMRSend pSend;

static NSString *sNPTitle, *sNPArtist;
static UIImage *sNPArt;
static NSData *sNPArtData;
static double sNPDuration, sNPElapsed, sNPRate;
static NSDate *sNPStamp;
static BOOL sNPPlaying, sNPHas;

+ (void)startMediaObserving {
    static BOOL started;
    if (started) return;
    started = YES;
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) return;
    pGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    pGetPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    pSend = dlsym(h, "MRMediaRemoteSendCommand");
    SBYMRRegister reg = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (reg) reg(dispatch_get_main_queue());
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSString *n in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification" ]) {
        [nc addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *x) { [SBYServices refreshNowPlaying]; }];
    }
    [self refreshNowPlaying];
}

+ (void)refreshNowPlaying {
    if (pGetInfo) {
        pGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            NSDictionary *d = (__bridge NSDictionary *)info;
            if (![d isKindOfClass:[NSDictionary class]] || !d.count) { sNPHas = NO; return; }
            NSString *title = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
            sNPHas = [title isKindOfClass:[NSString class]] && title.length;
            sNPTitle = sNPHas ? title : nil;
            NSString *artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
            sNPArtist = [artist isKindOfClass:[NSString class]] ? artist : nil;
            NSData *art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if ([art isKindOfClass:[NSData class]]) {
                if (![art isEqualToData:sNPArtData]) { sNPArtData = art; sNPArt = [UIImage imageWithData:art]; }
            } else { sNPArtData = nil; sNPArt = nil; }
            sNPDuration = [d[@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue];
            sNPElapsed = [d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
            sNPRate = [d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue];
            NSDate *ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
            sNPStamp = [ts isKindOfClass:[NSDate class]] ? ts : [NSDate date];
        });
    }
    if (pGetPlaying) pGetPlaying(dispatch_get_main_queue(), ^(Boolean p) { sNPPlaying = p; });
}

+ (NSDictionary *)nowPlaying {
    if (!sNPHas) return nil;
    double el = sNPElapsed;
    if (sNPPlaying && sNPStamp) el += [[NSDate date] timeIntervalSinceDate:sNPStamp] * (sNPRate > 0 ? sNPRate : 1);
    if (sNPDuration > 0) el = MIN(el, sNPDuration);
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"title"] = sNPTitle ?: @"";
    if (sNPArtist) r[@"artist"] = sNPArtist;
    if (sNPArt) r[@"artwork"] = sNPArt;
    r[@"duration"] = @(sNPDuration);
    r[@"elapsed"] = @(el);
    r[@"playing"] = @(sNPPlaying);
    return r;
}

+ (void)sendMediaCommand:(int)command {
    if (pSend) pSend(command, nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [SBYServices refreshNowPlaying]; });
}

#pragma mark - Battery

+ (NSInteger)batteryPercent {
    float l = [UIDevice currentDevice].batteryLevel;
    return l < 0 ? -1 : lround(l * 100);
}
+ (BOOL)isCharging {
    UIDeviceBatteryState st = [UIDevice currentDevice].batteryState;
    return st == UIDeviceBatteryStateCharging || st == UIDeviceBatteryStateFull;
}

#pragma mark - Weather (Open-Meteo, no API key)

static NSString *sTemp, *sSymbol, *sCondition, *sHighLow;
static NSDate *sLastFetch;
static BOOL sFetching;

+ (NSString *)temperatureString { return sTemp; }
+ (NSString *)weatherSymbol { return sSymbol; }
+ (NSString *)weatherCondition { return sCondition; }
+ (NSString *)weatherHighLow { return sHighLow; }

static void SBYWeatherInfo(int code, BOOL day, NSString **sym, NSString **desc) {
    if (code == 0) { *sym = day ? @"sun.max.fill" : @"moon.stars.fill"; *desc = day ? @"Sunny" : @"Clear"; }
    else if (code <= 2) { *sym = day ? @"cloud.sun.fill" : @"cloud.moon.fill"; *desc = @"Partly cloudy"; }
    else if (code == 3) { *sym = @"cloud.fill"; *desc = @"Cloudy"; }
    else if (code <= 48) { *sym = @"cloud.fog.fill"; *desc = @"Fog"; }
    else if (code <= 57) { *sym = @"cloud.drizzle.fill"; *desc = @"Drizzle"; }
    else if (code <= 67) { *sym = @"cloud.rain.fill"; *desc = @"Rain"; }
    else if (code <= 77) { *sym = @"cloud.snow.fill"; *desc = @"Snow"; }
    else if (code <= 82) { *sym = @"cloud.heavyrain.fill"; *desc = @"Showers"; }
    else if (code <= 86) { *sym = @"cloud.snow.fill"; *desc = @"Snow showers"; }
    else { *sym = @"cloud.bolt.rain.fill"; *desc = @"Thunderstorm"; }
}

+ (void)refreshWeatherIfNeeded {
    if (sFetching) return;
    if (sLastFetch && [[NSDate date] timeIntervalSinceDate:sLastFetch] < 15 * 60) return;
    sFetching = YES;
    BOOL f = [SBYPrefs fahrenheit];
    NSString *u = [NSString stringWithFormat:
        @"https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
        @"&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
        @"&timezone=auto&forecast_days=1%@",
        [SBYPrefs latitude], [SBYPrefs longitude], f ? @"&temperature_unit=fahrenheit" : @""];
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:u]
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSString *temp = nil, *sym = nil, *desc = nil, *hl = nil;
            if (data && !err) {
                id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSDictionary *cur = [j isKindOfClass:[NSDictionary class]] ? j[@"current"] : nil;
                NSDictionary *daily = [j isKindOfClass:[NSDictionary class]] ? j[@"daily"] : nil;
                if ([cur isKindOfClass:[NSDictionary class]] && [cur[@"temperature_2m"] isKindOfClass:[NSNumber class]]) {
                    temp = [NSString stringWithFormat:@"%ld°%@", lround([cur[@"temperature_2m"] doubleValue]), f ? @"F" : @"C"];
                    SBYWeatherInfo([cur[@"weather_code"] intValue], [cur[@"is_day"] intValue] != 0, &sym, &desc);
                }
                NSArray *hi = [daily isKindOfClass:[NSDictionary class]] ? daily[@"temperature_2m_max"] : nil;
                NSArray *lo = [daily isKindOfClass:[NSDictionary class]] ? daily[@"temperature_2m_min"] : nil;
                if ([hi isKindOfClass:[NSArray class]] && hi.count && [lo isKindOfClass:[NSArray class]] && lo.count)
                    hl = [NSString stringWithFormat:@"H:%ld°  L:%ld°", lround([hi[0] doubleValue]), lround([lo[0] doubleValue])];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                sFetching = NO;
                sLastFetch = [NSDate date];
                if (temp) {
                    sTemp = temp; sSymbol = sym; sCondition = desc; sHighLow = hl;
                    [[NSNotificationCenter defaultCenter] postNotificationName:SBYServicesDidUpdate object:nil];
                }
            });
        }];
    [t resume];
}

#pragma mark - Calls

static NSString *sCallState;
static NSDate *sCallConnectedAt;

static id SBYCallCenter(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_NOW); });
    Class c = NSClassFromString(@"TUCallCenter");
    return [c respondsToSelector:@selector(sharedInstance)] ? [c performSelector:@selector(sharedInstance)] : nil;
}

static id SBYTopCall(void) {
    id cc = SBYCallCenter();
    SEL sel = NSSelectorFromString(@"currentCalls");
    NSArray *calls = [cc respondsToSelector:sel] ? [cc performSelector:sel] : nil;
    if (![calls isKindOfClass:[NSArray class]] || !calls.count) return nil;
    for (id call in calls) {            // prefer a ringing call
        @try { if ([[call valueForKey:@"status"] intValue] == 4) return call; } @catch (__unused NSException *e) {}
    }
    return calls.firstObject;
}

static NSString *SBYCallString(id obj, NSString *key) {
    @try { id v = [obj valueForKey:key]; return [v isKindOfClass:[NSString class]] && [v length] ? v : nil; }
    @catch (__unused NSException *e) { return nil; }
}

+ (BOOL)callAPIAvailable {
    id cc = SBYCallCenter();
    return cc && [cc respondsToSelector:NSSelectorFromString(@"currentCalls")]
              && [cc respondsToSelector:NSSelectorFromString(@"answerCall:")]
              && [cc respondsToSelector:NSSelectorFromString(@"disconnectCall:")];
}

+ (void)setCallState:(NSString *)state {
    if ([state isEqualToString:@"connected"] && ![sCallState isEqualToString:@"connected"]) sCallConnectedAt = [NSDate date];
    if (![state isEqualToString:@"connected"]) sCallConnectedAt = nil;
    sCallState = state;
}
+ (NSString *)callState { return sCallState; }

+ (NSDictionary *)callInfo {
    if (!sCallState) return nil;
    id call = SBYTopCall();
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"state"] = sCallState;
    NSString *name = SBYCallString(call, @"displayName");
    NSString *number = nil;
    @try { number = SBYCallString([call valueForKey:@"handle"], @"value"); } @catch (__unused NSException *e) {}
    d[@"name"] = name ?: number ?: @"Unknown";
    if (number) d[@"number"] = number;
    if (sCallConnectedAt) d[@"since"] = sCallConnectedAt;
    return d;
}

+ (void)answerCall {
    id cc = SBYCallCenter(), call = SBYTopCall();
    SEL s = NSSelectorFromString(@"answerCall:");
    if (call && [cc respondsToSelector:s]) [cc performSelector:s withObject:call];
}

+ (void)endCall {
    id cc = SBYCallCenter(), call = SBYTopCall();
    SEL s = NSSelectorFromString(@"disconnectCall:");
    if (call && [cc respondsToSelector:s]) [cc performSelector:s withObject:call];
}

#pragma mark - Ringing alarm (best effort)

static NSDate *sWatchDate, *sRingingSince;
static id sWatchAlarm, sRingingAlarm;
static CFAbsoluteTime sLastAlarmCheck;

+ (void)updateAlarmState {
    NSDate *now = [NSDate date];
    // while the next alarm is close, check every call; otherwise every ~5 seconds
    NSTimeInterval gap = (sWatchDate && [sWatchDate timeIntervalSinceNow] < 6) ? 0 : 5.0;
    if (CFAbsoluteTimeGetCurrent() - sLastAlarmCheck < gap) return;
    sLastAlarmCheck = CFAbsoluteTimeGetCurrent();

    if (sRingingSince) {
        if ([now timeIntervalSinceDate:sRingingSince] > 300) [self clearAlarmRinging]; // never stay up longer than 5 minutes
    } else if (sWatchDate && [now compare:sWatchDate] != NSOrderedAscending) {
        if ([now timeIntervalSinceDate:sWatchDate] < 120) { sRingingSince = sWatchDate; sRingingAlarm = sWatchAlarm; }
        sWatchDate = nil; sWatchAlarm = nil;
    }
    NSDate *next = nil;
    id alarm = SBYNextAlarmObject(&next);
    if (alarm && [next timeIntervalSinceDate:now] > 0) {
        if (![next isEqualToDate:sWatchDate]) { sWatchDate = next; sWatchAlarm = alarm; }
    } else if (!alarm && sWatchDate && [sWatchDate timeIntervalSinceDate:now] > 0) {
        sWatchDate = nil; sWatchAlarm = nil;   // the alarm was turned off or deleted
    }
}

+ (BOOL)alarmRinging { return sRingingSince != nil; }

+ (BOOL)alarmAPIAvailable {
    id m = SBYAlarmManagerInstance();
    return m && [m respondsToSelector:NSSelectorFromString(@"snoozeAlarmWithIdentifier:")]
             && [m respondsToSelector:NSSelectorFromString(@"dismissAlarmWithIdentifier:")];
}

+ (NSDictionary *)ringingAlarm {
    if (!sRingingSince) return nil;
    NSString *label = SBYCallString(sRingingAlarm, @"title") ?: SBYCallString(sRingingAlarm, @"label");
    return @{ @"label": label ?: @"Alarm", @"since": sRingingSince };
}

static void SBYAlarmAction(NSString *selName) {
    id m = SBYAlarmManagerInstance();
    SEL sel = NSSelectorFromString(selName);
    if (!sRingingAlarm || ![m respondsToSelector:sel]) return;
    @try {
        id ident = [sRingingAlarm valueForKey:@"alarmID"];
        if (ident) [m performSelector:sel withObject:ident];
    } @catch (__unused NSException *e) {
        @try { [m performSelector:sel withObject:SBYCallString(sRingingAlarm, @"alarmIDString")]; } @catch (__unused NSException *e2) {}
    }
}

+ (void)snoozeAlarm { SBYAlarmAction(@"snoozeAlarmWithIdentifier:"); [self clearAlarmRinging]; sLastAlarmCheck = 0; }
+ (void)stopAlarm { SBYAlarmAction(@"dismissAlarmWithIdentifier:"); [self clearAlarmRinging]; sLastAlarmCheck = 0; }
+ (void)clearAlarmRinging { sRingingSince = nil; sRingingAlarm = nil; }

@end
