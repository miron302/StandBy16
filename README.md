# StandBy16

StandBy for iPhones on iOS 16. Plug in, lock, turn it sideways, and your phone becomes a bedside clock.
Made for iPhone X on iOS 16 with a rootless jailbreak (palera1n / Dopamine). **Version 1.0.3**

## Install
Install the `.deb` with Sileo or Filza, then respring. Open **Settings > StandBy16** to customize it.

## Using it
- Lock the phone, put it on a charger and turn it sideways. StandBy appears on its own.
- **Swipe left / right** to switch between Widgets and Clocks. **Swipe up / down** to change the clock style
  (Digital, Analog, Solar, Float, Float Color, World, Bold) or to scroll a widget stack.
- **Long-press** a widget stack to edit it. **Long-press** a clock to try a quick color.
- **Swipe up from the bottom edge** to leave StandBy.
- Night mode turns everything red (or your own color) in a dark room.
- **Always On** (Settings > StandBy16 > Display) keeps StandBy lit and dims it after 15 seconds; touch to brighten.
  To turn the screen off, swipe up from the bottom edge to leave StandBy, then press the side button.
- Now Playing, timers, alarms, notifications and calls take over the screen when they happen.

## Settings
- **Colors:** pick your own color for normal mode and for night mode.
- **Night mode:** Automatic, Always or Never.
- **Show:** turn Now Playing, Timers, Notifications, Calls, Alarms and Smart Rotate on or off.
- **Weather:** your city and coordinates for the weather widget and world clock.
- **Preview:** see StandBy right now without plugging in, or open the Preview app.
- **Advanced > Trigger Methods:** only if StandBy won't start. Every change asks for confirmation first.

## If StandBy doesn't appear
1. Settings > StandBy16 > Preview > **Preview StandBy**. If it shows, the UI is fine.
2. Advanced > Trigger Methods > **Test mode** shows it whenever the phone is locked.
3. Send the log at `/var/mobile/Library/Logs/StandBy16.log` (Filza > Share) when asking for help.

## Build from source
Needs [Theos](https://theos.dev). Run `make clean package` (rootless by default), then check the package with
`dpkg-deb -I packages/*.deb | grep Architecture` (should say `iphoneos-arm64`).
