# OLEDim

A tiny macOS menu bar app that controls the brightness of external monitors, built with OLED displays in mind.

macOS can't change the brightness of most external monitors. Windows can, because it talks to the monitor over **DDC/CI**. OLEDim does the same on Apple Silicon Macs, and adds two things OLED owners care about:

- **Match room light**: reads your MacBook's ambient light sensor and sets the monitor's brightness to match.
- **Match MacBook screen**: keeps the monitor in sync with your built-in display, so the brightness keys (and macOS auto-brightness) control both.
- In either mode, nudge the slider and it learns your preference, like "10% dimmer than my MacBook".
- **Dim when idle**: drops brightness after a few minutes of inactivity to reduce burn-in, and brings it back the moment you touch the mouse or keyboard. It won't dim while a video or call is keeping the screen awake.

Plus a brightness slider, one-click presets, smooth fades, and launch at login. No dependencies, no network access, a few hundred lines of Swift.

## Requirements

- Apple Silicon Mac (M1 or later), macOS 13+
- A monitor with DDC/CI support, connected over USB-C / Thunderbolt / DisplayPort. The built-in HDMI port on M1 and base M2 Macs doesn't pass DDC.
- The two matching modes need a MacBook with the lid open (that's where the light sensor and built-in screen are). They pause in clamshell mode.

Tested on an MSI MPG272UX OLED with an M3 Pro MacBook Pro.

## Install

Build from source (needs Xcode or the Command Line Tools):

```bash
git clone https://github.com/<you>/OLEDim.git
cd OLEDim
./scripts/build-app.sh
open dist/OLEDim.app
```

Move `dist/OLEDim.app` to `/Applications` to keep it.

## Command line

The same binary works as a CLI:

```bash
/Applications/OLEDim.app/Contents/MacOS/OLEDim list      # external displays found
/Applications/OLEDim.app/Contents/MacOS/OLEDim get       # current brightness
/Applications/OLEDim.app/Contents/MacOS/OLEDim set 40    # set brightness (0-100)
/Applications/OLEDim.app/Contents/MacOS/OLEDim login on  # start at login (or: login off)
```

## Troubleshooting

- **Nothing happens:** turn on **DDC/CI** in your monitor's on-screen menu.
- **The value changes but the screen doesn't:** HDR and some picture modes lock brightness. Switch to a standard SDR mode.
- **Running MonitorControl or similar too:** they work side by side, but both can write brightness, so use automatic brightness in only one of them.

## How it works

- Brightness is set over DDC/CI (VCP code `0x10`) using the private `IOAVService` I2C calls on Apple Silicon, the same approach as [m1ddc](https://github.com/waydabber/m1ddc) and [MonitorControl](https://github.com/MonitorControl/MonitorControl).
- Room light comes from the ambient light sensor via the private `IOHIDEventSystemClient` API. Readings are smoothed and mapped on a log curve between a darkest and brightest level you choose.
- The MacBook's brightness is read with the private `DisplayServicesGetBrightness` call.
- Idle time comes from `CGEventSource`. Video and call detection checks for `PreventUserIdleDisplaySleep` power assertions.

Because these are private APIs, a future macOS update could break them.

## License

MIT
