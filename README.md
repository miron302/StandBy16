# StandBy16

iOS 17 StandBy for iOS 16. Plug in, lock, turn the phone sideways.
Built for iPhone X on iOS 16.7.x (A11 / palera1n). Untested on other devices.

## Views (modelled on real StandBy)
Swipe left/right between the two views:
- **Widgets**: two stacks side by side, each scrolls vertically (touch the side you want to scroll).
  Widgets: Clock, Analog, Battery, Date, Weather, World Time, Alarm. **Long-press a stack** to edit it
  (tap -/+ to remove/add widgets, tap Done). **Smart Rotate** picks a relevant widget (alarm soon, morning weather)
  after you haven't touched it for 5 minutes.
- **Clock**: swipe up/down to change style: Digital - Analog - Solar - Float - World - Bold.
  Long-press to cycle the colour (ignored in red night mode).
- **Now Playing** takes over the screen automatically while media plays (tap prev / play-pause / next).
- **Timer** (Clock app) takes over like a Live Activity.
- **Notifications** show as an enlarged banner for a few seconds.
- **Calls**: StandBy steps aside so the normal incoming-call screen is never covered.
Swipe left/right on a Now Playing / Timer takeover to dismiss it. Swipe up from the very bottom edge to leave
StandBy and get the normal lock screen back (it returns when you unplug/replug or rotate).
It reopens on the last view/style you used. Night mode turns everything red-monochrome and dims the screen.
Activation = locked + charging + landscape + held still for ~0.8s. With motionToWake on, a night-mode screen
that has slept wakes when it senses movement.

## Build (on your hackintosh, with Theos installed)
    export THEOS=~/theos
    make package
    make package install THEOS_DEVICE_IP=<iphone ip>     # or copy the .deb over and install it with Sileo/dpkg

Makefile is rootless (palera1n default). For a rootful jailbreak delete the `THEOS_PACKAGE_SCHEME` line.
Then `killall -9 SpringBoard` (or just respring).

## Settings (no prefs pane yet)
Run on the phone as mobile, then respring if a value doesn't pick up:
    defaults write com.miron302.standby16 cityName -string "London"
    defaults write com.miron302.standby16 latitude -float 51.5072
    defaults write com.miron302.standby16 longitude -float -0.1276
    defaults write com.miron302.standby16 nightMode -int 0        # 0 ambient estimate, 1 always red, 2 never red, 3 by hours
    defaults write com.miron302.standby16 ambientThreshold -float 0.25   # system brightness below this = dark room
    defaults write com.miron302.standby16 nightStart -int 21      # only used by nightMode 3
    defaults write com.miron302.standby16 nightEnd -int 7
    defaults write com.miron302.standby16 keepAwake -bool false   # false = screen sleeps, tap to wake (like non-Always-On iPhones)
    defaults write com.miron302.standby16 nightBrightness -float 0.04   # 0 = don't touch brightness
    defaults write com.miron302.standby16 requireCharging -bool true
    defaults write com.miron302.standby16 fahrenheit -bool false
    defaults write com.miron302.standby16 enabled -bool true
    defaults write com.miron302.standby16 smartRotate -bool true
    defaults write com.miron302.standby16 motionToWake -bool true
    defaults write com.miron302.standby16 notifications -bool true
    defaults write com.miron302.standby16 nowPlaying -bool true
    defaults write com.miron302.standby16 timerActivity -bool true
    defaults write com.miron302.standby16 windowLevel -int 10000   # lower it if the overlay covers things it shouldn't

lat/lon/city drive the World page marker and the weather (Open-Meteo, no API key).

## How it works
SpringBoard hook starts SBYController. It watches charging (UIDevice), orientation (UIDevice),
and lock + screen-blank state (Darwin notifications com.apple.springboard.lockstate / hasBlankedScreen).
When all line up it shows a UIWindow above the lock screen, hand-rotated to landscape (the lock screen
is portrait only). Pixel shift every minute for OLED burn-in. Night mode = red palette + low brightness.

## Differences from real StandBy
- Ambient light: apps can't read the light sensor from SpringBoard without private HID code, so "dark room"
  is estimated from the system auto-brightness level at the moment StandBy appears (re-checked each time).
- No Photos view (removed on purpose), no MagSafe-location memory (iPhone X has no MagSafe), no Widget Suggestions,
  no third-party/interactive widgets, Calendar and Reminders widgets (need entitlements / WidgetKit hosting).
- Calls: it hides instead of showing a landscape Contact Poster. Siri: not enlarged.
- Live Activities: only the Clock-app timer (other apps' ActivityKit data isn't readable from SpringBoard).

## Known "might need tuning on 16.7" spots (written without a device to test)
1. keepAwake=true (optional): -[SBYController keepAwake] probes SBBacklightController selectors + an IOKit assertion.
   If the screen still auto-locks while docked, hook the idle timer policy instead (class-dump SpringBoard).
2. Window creation in SpringBoard on iOS 16 sometimes wants a scene. If the overlay never appears,
   check `oslog`/syslog for StandBy16 and try creating the window with a UIWindowScene from
   UIApplication.sharedApplication.connectedScenes.
3. Alarm complication uses MTAlarmManager -nextAlarmSync (private, via runtime lookup). Nothing shows if it's missing.
5. Now Playing uses MediaRemote, timers use MTTimerManager, notifications hook BBServer publishBulletin*:
   all runtime-looked-up private APIs; if one is missing on 16.7.x that single feature just stays quiet.
6. Motion-to-wake calls -[SBBacklightController turnOnScreenFullyWithBacklightSource:] (selector may differ).

Version: 1.0.0
