#import <UIKit/UIKit.h>

extern NSString *const SBYServicesDidUpdate;

@interface SBYServices : NSObject
+ (BOOL)is24h;
+ (NSString *)timeString;        // "18:52" or "6:52"
+ (NSString *)upperDateString;   // "WED 28"
+ (NSString *)weekdayShort;      // "Wed"
+ (NSString *)monthShort;        // "Oct"
+ (NSString *)dayNumber;         // "28"
+ (NSString *)alarmString;       // nil if no alarm in the next 24h
+ (NSDate *)nextAlarmDate;       // nil if no alarm in the next 24h

// Clock-app timer (shown like a Live Activity). Returns NO when no timer is running.
+ (BOOL)timerRemaining:(NSTimeInterval *)remaining total:(NSTimeInterval *)total;

// Now Playing via MediaRemote (runtime-loaded private framework).
+ (void)startMediaObserving;
+ (void)refreshNowPlaying;
+ (NSDictionary *)nowPlaying;    // nil if nothing. keys: title, artist, artwork (UIImage?), duration, elapsed, playing
+ (void)sendMediaCommand:(int)command; // 2 play/pause, 4 next, 5 previous
+ (NSDateComponents *)nowComponents; // hour, minute, second, nanosecond

+ (NSInteger)batteryPercent;     // -1 if unknown
+ (BOOL)isCharging;

// Weather (Open-Meteo). All nil until the first fetch succeeds.
+ (NSString *)temperatureString; // "12°C"
+ (NSString *)weatherSymbol;     // SF Symbol name
+ (NSString *)weatherCondition;  // "Light rain"
+ (NSString *)weatherHighLow;    // "H:14°  L:8°"
+ (void)refreshWeatherIfNeeded;
@end
