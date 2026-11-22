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

## Check the package before installing
After `make clean package`, confirm it is a rootless package:
    dpkg-deb -I packages/*.deb | grep -E "Architecture|Depends"   # must say iphoneos-arm64
    dpkg-deb -c packages/*.deb | head                              # paths must start with ./var/jb/
If it says `iphoneos-arm`, the build was rootful and Sileo will refuse it on a rootless jailbreak
("Depends mobilesubstrate:iphoneos-arm"). Always run `make clean` first so no stale staging folder is reused.

## Already have a rootful .deb? Convert it on the phone (NewTerm, no computer)
A build service that ignores the rootless setting produces `iphoneos-arm`, which Sileo refuses on a rootless jailbreak.
StandBy16 has no rootful/rootless code differences, so the package can simply be repacked:
    D=/path/to/com.miron302.standby16_1.0.2_iphoneos-arm.deb
    rm -rf ~/sby && mkdir -p ~/sby
    dpkg-deb -R "$D" ~/sby
    mkdir -p ~/sby/var/jb
    for d in Library Applications usr; do [ -d ~/sby/$d ] && mv ~/sby/$d ~/sby/var/jb/; done
    sed -i 's/^Architecture: .*/Architecture: iphoneos-arm64/' ~/sby/DEBIAN/control
    dpkg-deb --root-owner-group -b ~/sby ~/StandBy16_rootless.deb
Then open ~/StandBy16_rootless.deb in Sileo/Filza to install it and respring.

## Build (on your hackintosh, with Theos installed)
    export THEOS=~/theos
    make package
    make package install THEOS_DEVICE_IP=<iphone ip>     # or copy the .deb over and install it with Sileo/dpkg

Makefile is rootless (palera1n default). For a rootful jailbreak delete the `THEOS_PACKAGE_SCHEME` line.
Then `killall -9 SpringBoard` (or just respring).

## Settings
Settings > StandBy16 (needs PreferenceLoader, installed automatically as a dependency). The same keys work with `defaults write`:

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

Version: 1.0.2

## Previewing without the trigger sequence
- Settings > StandBy16 > Preview > **Preview StandBy now** (flip the switch): shows StandBy for 25s in a separate window,
  even unlocked. Swipe up from the bottom edge to close it early.
- **Open preview app** (or tap the StandBy16 icon on the home screen): the same pages as an ordinary landscape app.
  Swipe like real StandBy; double-tap toggles night mode; long-press for colours / stack editing.
If the preview app looks right but the lock-screen version doesn't appear, the UI is fine and the problem is the
trigger/hook, which the log will show.

## Trigger method settings (advanced)
Settings has a second entry, **StandBy16 Trigger Methods**. It lets you swap how each part of the trigger is detected:
orientation (accelerometer / system / either / ignore), lock state (lock manager / notification / either),
screen state (backlight / notification / ignore), settle delay (wait / off) and overlay (inside lock screen / separate window).
The first option in every list is the stable default. Any change shows a WARNING popup: **Continue changing** applies it,
**Cancel** puts that setting back to its default. The log line shows the active methods as
`methods(orient,lock,screen,still,overlay)=00000`.
If a method breaks the trigger, use **Reset all to defaults** at the bottom of that page.

## Looks and feel
- StandBy covers the whole lock screen: torch, camera, padlock, "Swipe up to unlock", the status bar and the home
  indicator are hidden while it is up and restored (faded back in) when it closes. Turn this off with
  Settings > StandBy16 > Troubleshooting > Hide iOS lock screen UI. The log lists every window and every system view
  it hides, so anything that still shows can be targeted.
- If it is rotated the wrong way, Settings > StandBy16 Trigger Methods > Orientation direction > Flipped 180°.
- Pages follow your finger when you swipe (rubber-band) and spring back; page changes spring; the time dissolves when
  the minute changes; Now Playing has an artwork-colour glow, the artwork shrinks while paused, and the buttons press.

## Screen off / wake
StandBy now stays loaded while the screen is off, so waking the phone shows StandBy immediately instead of flashing the
iOS lock screen first (Settings > StandBy16 > Stay ready while screen is off). While the screen is off it only refreshes
every ~5s, and everything is refreshed the instant the screen wakes.
"Keep screen on" (always-on) is best-effort: the log lists the idle-timer methods this iOS has
(`SBBacklightController idle-related methods: ...`) so the right one can be wired up.

## Stability notes
- Every state check and the 4Hz redraw run inside @try/@catch, so a bad value can't take SpringBoard down.
- A 2s poll re-checks lock/charge/screen/orientation in case a system notification never arrives.
- StandBy keeps itself on top of the lock screen's views and re-sizes if the lock screen re-lays out.
- The log gets `dylib loaded in SpringBoard` as soon as the tweak is injected, and `started` once the controller runs.

## If it does nothing
StandBy now draws *inside* the lock screen (it hooks CSCoverSheetViewController) instead of a separate window.
1. Check the tweak is loaded: after a respring, `/var/mobile/Library/Logs/StandBy16.log` should contain a `started` line
   and `lock screen view controller captured`. No `started` line = the dylib isn't loading (check it is in
   /var/jb/Library/MobileSubstrate/DynamicLibraries/ and that your jailbreak is rootless).
2. Settings > StandBy16 > Troubleshooting > **Test mode**, respring, lock, wake the screen. StandBy should appear.
3. Turn Test mode off, plug in, lock, turn sideways. The log shows
       force=0 enabled=1 locked=1 charging=1 landscape=1 blanked=0 ... host=1 -> SHOW
   Whichever field is wrong is the culprit (`host=0` means the lock screen controller was never captured;
   try "Use separate window").
With a computer, `idevicesyslog | grep StandBy16` shows the same lines live.
