# OLEDim

Menu bar app (Swift, no dependencies) that sets external monitor brightness over DDC/CI on Apple Silicon. Public repo: https://github.com/davyprotan/OLEDim (MIT).

## Build, install, test

- `./scripts/build-app.sh` builds `dist/OLEDim.app`; `--install` also replaces `/Applications/OLEDim.app` and relaunches it. Settings live in UserDefaults (`io.github.oledim`) and survive reinstalls.
- The binary doubles as a CLI: `OLEDim list | get | set <0-100> | login on|off`.
- Ground truth for what the monitor is actually at: `m1ddc display 2 get luminance` (`brew install m1ddc`; display 2 is the MSI MPG272UX on the dev Mac).
- No unit tests. Verify on hardware: read brightness back after every change.

## Files

| File | Why it exists |
|---|---|
| `DDC.swift` | I2C read/write via private `IOAVService*` symbols; finds external displays through `DCPAVServiceProxy` nodes. |
| `BrightnessController.swift` | Serialises DDC writes on one queue; a generation counter cancels in-flight fades so slider drags don't pile up. `isReady` gates everything until the real brightness is read. |
| `Automation.swift` | Brightness modes (room light / match MacBook), learned offsets, idle dimming. |
| `AmbientLight.swift` / `BuiltInDisplay.swift` | Private `IOHIDEventSystemClient` (light sensor, lux) and `DisplayServicesGetBrightness` (MacBook screen, 0–1). |
| `Settings.swift` / `SettingsView.swift` / `AppDelegate.swift` | Preferences, SwiftUI settings window, NSStatusItem menu. |

## Gotchas

- **Private APIs.** DDC, the light sensor and MacBook brightness all use undocumented symbols. A macOS update can break any of them; check these first if something stops working.
- **Startup race.** Automation must not act before `controller.isReady`. Before that fix, first-run calibration used the placeholder brightness (50) and visibly dimmed the monitor.
- **Calibration runs once per mode**, keyed `calibrated.<mode raw value>`. To recalibrate: `defaults delete io.github.oledim "calibrated.Match MacBook screen"` (or the room-light key) and reset the offset in Settings.
- Both automatic modes pause with the lid closed: the light sensor is beside the built-in screen.
- Sliders in `SettingsView` round in the binding instead of using `step:`, which draws a tick for every 1%.
- `swift build --show-bin-path` is the binary location; it's `.build/out/Products/Release`, not the older `.build/<triple>/release`.

## Releasing

1. `VERSION=x.y.z ./scripts/build-app.sh`, then bump the default `VERSION` in that script.
2. `ditto -c -k --keepParent dist/OLEDim.app dist/OLEDim.zip`
3. `gh release create vx.y.z dist/OLEDim.zip --title "OLEDim x.y.z" --notes "..."`
4. Download the asset back and check `codesign --verify --strict` and the version in `Info.plist`.

The app is ad-hoc signed, not notarized; the README tells users to right-click → Open the first time.

Commits use the GitHub no-reply email; GitHub blocks pushes that expose a personal email. History was rewritten once (2026-10-14) to remove it; the `v0.1.0` tag was moved to the rewritten commit.
