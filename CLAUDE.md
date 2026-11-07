# OLEDim

Menu bar app (Swift, no dependencies) that sets external monitor brightness over DDC/CI on Apple Silicon. Public repo: https://github.com/davyprotan/OLEDim (MIT).

## Build, install, test

- `./scripts/build-app.sh` builds `dist/OLEDim.app`; `--install` also replaces `/Applications/OLEDim.app` and relaunches it. Settings live in UserDefaults (`io.github.oledim`) and survive reinstalls.
- The binary doubles as a CLI: `OLEDim list | get | set <0-100> | login on|off`.
- Ground truth for what the monitor is actually at: `m1ddc display 2 get luminance` (`brew install m1ddc`; display 2 is the MSI MPG272UX on the dev Mac). Not installed as of 2026-10-30; `OLEDim get` reads the same register.
- To test sync: `OLEDim set 70` behind the app's back; in an automatic mode it should snap back within ~30s.
- To test following: in Match MacBook mode, press the brightness keys with the menu closed, then open; the monitor should follow within 1-2s. Expected level is `autoMin + (autoMax - autoMin) * macBrightness + macOffset`, clamped to 0-100 (`defaults read io.github.oledim macOffset`).
- No unit tests. Verify on hardware: read brightness back after every change.

## Files

| File | Why it exists |
|---|---|
| `DDC.swift` | I2C read/write via private `IOAVService*` symbols; finds external displays through `DCPAVServiceProxy` nodes. |
| `BrightnessController.swift` | Serialises DDC writes on one queue; a generation counter cancels in-flight fades so slider drags don't pile up. `isReady` gates everything until the real brightness is read. `resync()` re-reads the monitor; a reading taken before a newer `set()` is dropped. |
| `Automation.swift` | Brightness modes (room light / match MacBook), learned offsets, idle dimming. |
| `AmbientLight.swift` / `BuiltInDisplay.swift` | Private `IOHIDEventSystemClient` (light sensor, lux) and `DisplayServicesGetBrightness` (MacBook screen, 0–1). |
| `SoftwareDimmer.swift` | Levels below 0 (down to -75): the monitor stays at DDC 0 and the external displays' gamma table is scaled to take away the rest of the light. |
| `Settings.swift` / `SettingsView.swift` / `AppDelegate.swift` | Preferences, SwiftUI settings window, NSStatusItem menu. |

## Gotchas

- **Private APIs.** DDC, the light sensor and MacBook brightness all use undocumented symbols. A macOS update can break any of them; check these first if something stops working.
- **Startup race.** Automation must not act before `controller.isReady`. Before that fix, first-run calibration used the placeholder brightness (50) and visibly dimmed the monitor.
- **Calibration runs once per mode**, keyed `calibrated.<mode raw value>`. To recalibrate: `defaults delete io.github.oledim "calibrated.Match MacBook screen"` (or the room-light key) and reset the offset in Settings.
- **DDC reads are flaky; never assume a second read matches the first.** The monitor can stop answering mid-rescan (wake, replug). `lazy.compactMap { $0.read(...) }.first` re-runs the closure and force-unwraps, which crashed the app on 2026-10-16. Read once into a local.
- **`controller.brightness` is a claim, not a fact.** `set()` updates it before the write lands, and the monitor changes behind our back (wake at its own level, its own buttons, replug). Automation only writes when the target differs from it, so a stale value never self-corrects. That's why the app reads back after a failed write, after wake (3s, 10s) and every 30s ([#2](https://github.com/davyprotan/OLEDim/pull/2)). Don't remove the periodic resync to save I2C traffic.
- **The automation timer must stay in `.common` run-loop mode.** The default mode doesn't fire during menu tracking or slider drags, so the monitor ignored the brightness keys while the menu was open ([#2](https://github.com/davyprotan/OLEDim/pull/2)).
- **Dragging the menu slider rewrites the learned offset, which can make the keys look dead.** At a `macOffset` of -24, the monitor sits at 0 once the MacBook is below about 20% and tops out near 76%. Check the offset before debugging "ignores the keys".
- **"It didn't start" usually means it crashed.** Launch at login only fires at login; nothing relaunches the app after a crash. Check `~/Library/Logs/DiagnosticReports/OLEDim-*.ips` first; symbolicate with `xcrun atos -i -o /Applications/OLEDim.app/Contents/MacOS/OLEDim -l <base> <addr>`.
- `OLEDim login` with any argument other than `off` turns launch at login **on**; there's no read-only status command.
- **DDC 0 is not black.** The MPG272UX still gives off a fair amount of light at 0, so levels below 0 are software dimming (gamma), not a monitor setting. `OLEDim get` reads 0 for any level ≤ 0; check the gamma with `CGGetDisplayTransferByTable` (1.0 at the top = no dimming, `light^(1/2.2)` otherwise). macOS drops the gamma table on quit, crash, reconfigure and sometimes wake, so `resync()` and `rescan()` reapply it. It replaces the display's calibration curve while active, and dims every non-built-in display, not only DDC ones.
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
