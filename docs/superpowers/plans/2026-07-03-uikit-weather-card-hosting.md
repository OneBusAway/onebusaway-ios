# UIKit Weather Card via UIHostingController Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `UIAlertController` weather popup in `MapViewController` with the existing SwiftUI `WeatherDetailPopup` card, hosted via `UIHostingController`, and delete the now-unused legacy alert path.

**Architecture:** Introduce a thin SwiftUI wrapper (`WeatherDetailPopupHost`) that binds `MapViewModel` to `WeatherDetailPopup` and closes itself through `@Environment(\.dismiss)`. `MapViewController.showWeather()` presents a `UIHostingController` of that wrapper `.overFullScreen` with a clear background so the card's own dim overlay and animations own the visual experience. Once the alert path is gone, `WeatherDisplay+LegacyAlert.swift` and `WeatherDisplay.todaySummary` are deleted along with the tests that only cover them.

**Tech Stack:** Swift 5.3+, iOS 17.0+, UIKit + SwiftUI interop (`UIHostingController`, `@Environment(\.dismiss)`, `@ObservedObject`), Nimble tests, `xcodebuild` on iPhone 16 simulator.

## Global Constraints

- Target iOS: 17.0+ (from CLAUDE.md — do not use `iOS 18`-only APIs).
- Swift version: 5.3+.
- `OBAKitCore` must remain application-extension-safe; only touch `OBAKit` UI-layer code plus `OBAKitTests`.
- Project regeneration required before building: `scripts/generate_project OneBusAway`.
- SwiftLint via `scripts/swiftlint.sh` must pass; disabled rules listed in `.swiftlint.yml`.
- No auto-commits: only stage and commit when the plan step explicitly says so.
- Commit messages are a single subject line, no body, no `Co-Authored-By` trailer.
- `WeatherForecast.todaySummary` in OBAKitCore stays — it is an API field, not the UI mirror being deleted.

---

## File Structure

**Create**
- `OBAKit/Sheet/Root/WeatherDetailPopupHost.swift` — SwiftUI wrapper binding `MapViewModel` into `WeatherDetailPopup` and closing itself via `@Environment(\.dismiss)`.

**Modify**
- `OBAKit/Mapping/MapViewController.swift` — rewrite `showWeather()` (lines 434–445) to present `UIHostingController<WeatherDetailPopupHost>` instead of the `UIAlertController`.
- `OBAKit/ViewModels/MapViewModel/WeatherDisplay.swift` — remove the `todaySummary` stored property and its assignment in `init` (lines 36–41, 58).
- `OBAKitTests/Weather/WeatherDisplayTests.swift` — prune legacy-alert assertions and rename the surviving fixture test.

**Delete**
- `OBAKit/ViewModels/MapViewModel/WeatherDisplay+LegacyAlert.swift` — the whole file; no consumers remain after `showWeather()` is rewritten.

Files split by responsibility: the wrapper view is its own file next to the other Sheet/Root SwiftUI views (`WeatherButton.swift`, `WeatherDetailPopup.swift`, `MapPanelRootView.swift`) so the presentation-layer surface reads at a glance.

---

## Task 1: Add `WeatherDetailPopupHost` SwiftUI wrapper

**Files:**
- Create: `OBAKit/Sheet/Root/WeatherDetailPopupHost.swift`

**Interfaces:**
- Consumes: `MapViewModel` (has `@Published var weatherDisplay: WeatherDisplay?` — see `OBAKit/ViewModels/MapViewModel/MapViewModel.swift`), `WeatherDetailPopup(display:isPresented:)` (see `OBAKit/Sheet/Root/WeatherDetailPopup.swift:22-24`).
- Produces: `struct WeatherDetailPopupHost: View` with initializer `init(viewModel: MapViewModel)`. Task 2 uses this exact signature.

- [ ] **Step 1: Create the wrapper file**

Write `OBAKit/Sheet/Root/WeatherDetailPopupHost.swift`:

```swift
//
//  WeatherDetailPopupHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// UIKit-modal-hosted counterpart of the `WeatherDetailPopup` in
/// `MapPanelRootView`. Owns the presentation-state binding the card animates
/// against and forwards dismissal to the enclosing `UIHostingController`
/// via `@Environment(\.dismiss)` — so the SwiftUI exit transition plays
/// before UIKit tears the modal down.
///
/// `viewModel` is held as `@ObservedObject` (not a captured snapshot) so a
/// weather refresh that lands while the card is open updates the display in
/// place, matching the SwiftUI panel behavior (see `MapPanelRootView`).
struct WeatherDetailPopupHost: View {

    @ObservedObject var viewModel: MapViewModel

    /// Starts `true` so `WeatherDetailPopup`'s enter transition runs on
    /// appear. The card flips this to `false` on backdrop tap or close-button
    /// press, which triggers the exit animation and, via `onChange`, the
    /// UIKit dismissal below.
    @State private var isPresented = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WeatherDetailPopup(display: viewModel.weatherDisplay, isPresented: $isPresented)
            .onChange(of: isPresented) { _, newValue in
                if !newValue { dismiss() }
            }
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new file is picked up**

Run: `scripts/generate_project OneBusAway`
Expected: exits 0 with no errors; `OBAKit.xcodeproj` updated.

- [ ] **Step 3: Verify the new file compiles**

Run: `xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Sheet/Root/WeatherDetailPopupHost.swift
git commit -m "Add WeatherDetailPopupHost SwiftUI wrapper for UIKit modal"
```

---

## Task 2: Present `WeatherDetailPopupHost` from `MapViewController.showWeather()`

**Files:**
- Modify: `OBAKit/Mapping/MapViewController.swift:434-445`

**Interfaces:**
- Consumes: `WeatherDetailPopupHost(viewModel:)` from Task 1.
- Produces: nothing new; `showWeather()` retains its `@objc private` signature so `weatherButton`'s target/action wiring at `MapViewController.swift:428` still works.

- [ ] **Step 1: Replace `showWeather()` with the hosting-controller path**

In `OBAKit/Mapping/MapViewController.swift`, replace the `showWeather()` method (lines 434–445):

```swift
    @objc private func showWeather() {
        guard weatherDisplay != nil else { return }

        let host = UIHostingController(
            rootView: WeatherDetailPopupHost(viewModel: viewModel)
        )
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        present(host, animated: true)
    }
```

Explanation of the choices:
- `guard weatherDisplay != nil` mirrors the old guard so a tap while the button is somehow still visible without data is a no-op.
- `.overFullScreen` keeps the map beneath the popup visible, since the card supplies its own dim overlay (`Color.black.opacity(0.25)` inside `WeatherDetailPopup.swift:47`).
- `view.backgroundColor = .clear` prevents the hosting controller's default background from covering the map.
- The wrapper handles its own dismissal via `@Environment(\.dismiss)`, so `MapViewController` does not need to hold or observe the host.

- [ ] **Step 2: Confirm the file still compiles**

Run: `xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke check in the simulator**

1. Launch the app on iPhone 16 simulator.
2. Wait for the weather button in the `HoverBar` (right side) to show a temperature (fixture region will do).
3. Tap it — confirm the new card slides in with dim backdrop.
4. Tap the backdrop — confirm exit animation runs and the card is gone; the map and `HoverBar` remain interactive.
5. Re-open, tap the close button (`xmark`) — confirm same dismissal behavior.
6. Re-open, drag the FloatingPanel up behind the popup — confirm nothing bleeds over the card during dismissal.

Note the results (pass/fail per step) in the commit message context or a follow-up comment. Do not commit until all six pass.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Mapping/MapViewController.swift
git commit -m "Present new weather card from MapViewController via UIHostingController"
```

---

## Task 3: Delete the legacy alert extension

**Files:**
- Delete: `OBAKit/ViewModels/MapViewModel/WeatherDisplay+LegacyAlert.swift`
- Modify: `OBAKit/ViewModels/MapViewModel/WeatherDisplay.swift` (remove `todaySummary` property and its `init` assignment)

**Interfaces:**
- Consumes: nothing new.
- Produces: `WeatherDisplay` no longer exposes `.todaySummary` or `.legacyAlert`. Task 4 relies on this — its test edits assume neither property exists.

- [ ] **Step 1: Confirm nothing outside the legacy pair still calls `legacyAlert` or `WeatherDisplay.todaySummary`**

Run: `grep -rn "legacyAlert" --include="*.swift" .`
Expected: only matches are inside `WeatherDisplay+LegacyAlert.swift` (which we are deleting) and `OBAKitTests/Weather/WeatherDisplayTests.swift` (handled by Task 4).

Run: `grep -rn "WeatherDisplay" --include="*.swift" . | grep todaySummary`
Expected: only matches are in `OBAKit/ViewModels/MapViewModel/WeatherDisplay.swift` (the declaration and init) and `WeatherDisplay+LegacyAlert.swift`. If anything else shows up (e.g. a downstream white-label app read it), stop and re-evaluate before deleting.

- [ ] **Step 2: Delete the legacy alert extension file**

Run: `rm OBAKit/ViewModels/MapViewModel/WeatherDisplay+LegacyAlert.swift`

- [ ] **Step 3: Remove `todaySummary` from `WeatherDisplay`**

In `OBAKit/ViewModels/MapViewModel/WeatherDisplay.swift`:

Delete the property block at lines 36–41:

```swift
    /// One-sentence outlook from the Obaco `today_summary` field, used as the
    /// legacy `UIAlertController` title. Stored on the primary struct so the
    /// transitional `legacyAlert` computed accessor (see
    /// `WeatherDisplay+LegacyAlert.swift`) doesn't need to keep the heavyweight
    /// `WeatherForecast` alive.
    let todaySummary: String
```

Delete the init assignment at line 58:

```swift
        self.todaySummary = forecast.todaySummary
```

Leave everything else in `WeatherDisplay.swift` alone. `WeatherForecast.todaySummary` in OBAKitCore stays — it is the API model, not the display mirror.

- [ ] **Step 4: Regenerate the project and build**

Run: `scripts/generate_project OneBusAway`
Then: `xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

If the build fails on `WeatherDisplayTests.swift` because it still references `todaySummary` or `legacyAlert`, do NOT patch those references here — that is Task 4's job. Move to Task 4 and come back.

- [ ] **Step 5: Commit (only if the build passes; otherwise defer this commit until after Task 4)**

```bash
git add OBAKit/ViewModels/MapViewModel/WeatherDisplay.swift OBAKit/ViewModels/MapViewModel/WeatherDisplay+LegacyAlert.swift
git commit -m "Delete legacy weather alert extension and todaySummary mirror"
```

Note: `git add` on the deleted file records the deletion.

---

## Task 4: Prune legacy-alert test coverage

**Files:**
- Modify: `OBAKitTests/Weather/WeatherDisplayTests.swift`

**Interfaces:**
- Consumes: the smaller `WeatherDisplay` surface produced by Task 3.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Prune `legacyAlert` assertions from the fixture test**

In `OBAKitTests/Weather/WeatherDisplayTests.swift`:

Delete the block comment on lines 201–204 and replace it with a shorter one that reflects the surviving scope. Rename the test method. Delete the `LegacyAlert` assertion block on lines 225–232.

Replace lines 201–233 with:

```swift
    /// `WeatherDisplay` exists so the UIKit and SwiftUI surfaces can't drift —
    /// both consume the same Header/Stats/HourlyEntry slices. Pinning the
    /// derived strings from a fixture locks the contract so a formatter tweak
    /// that only updates one surface would fail here.
    func test_init_populatesHeaderStatsAndHourlyFromFixture() throws {
        let forecast = try loadPugetSoundForecast()
        let display = WeatherDisplay(forecast: forecast, locale: usLocale, now: pugetSoundNow, calendar: utcCalendar)

        // Header — derived from `current_forecast` + `region_name` + the
        // hourly window's hi/lo, not the calendar-day hi/lo.
        expect(display.header.regionName) == "Puget Sound"
        expect(display.header.iconName) == "clear-day"
        expect(display.header.currentTemp) == "71°"
        expect(display.header.chanceOfRainText) == "Chance of Rain: 0%"
        expect(display.header.highLowText).toNot(beNil())

        // Stats — current-hour wind / precip / feels-like.
        expect(display.stats.feelsLikeText) == "71°"
        expect(display.stats.precipText) == "0%"
        expect(display.stats.windText).to(contain("mph"))

        // Button pill mirrors the current temperature.
        expect(display.buttonTitle) == "71°"
    }
```

- [ ] **Step 2: Scan the file for any leftover `legacyAlert` or `todaySummary` references**

Run: `grep -n "legacyAlert\|todaySummary" OBAKitTests/Weather/WeatherDisplayTests.swift`
Expected: no matches.

If matches turn up (e.g. another test not visible in this plan's excerpt), remove just the offending assertions. If a whole test's only purpose is legacy-alert coverage, delete the entire test. Do not weaken assertions that also cover Header/Stats/HourlyEntry — keep those.

- [ ] **Step 3: Run the weather-focused tests**

Run:
```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/WeatherDisplayTests \
  -only-testing:OBAKitTests/WeatherFormatterTests \
  -only-testing:OBAKitTests/MapViewModelTests \
  -project 'OBAKit.xcodeproj' \
  -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: all three test suites PASS.

- [ ] **Step 4: Run the full unit test suite**

Run:
```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' \
  -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: PASS.

- [ ] **Step 5: SwiftLint clean**

Run: `scripts/swiftlint.sh`
Expected: exits 0 with no violations in the touched files.

- [ ] **Step 6: Commit**

```bash
git add OBAKitTests/Weather/WeatherDisplayTests.swift
git commit -m "Prune legacy weather alert assertions from WeatherDisplayTests"
```

If Task 3's commit was deferred because the build failed there, this commit should be preceded by that one — run the deferred `git add` + `git commit` from Task 3 Step 5 first, then this Task 4 commit.

---

## Self-Review

**Spec coverage**

- Component 1 (`WeatherDetailPopupHost`): Task 1.
- Component 2 (`MapViewController.showWeather()` rewrite): Task 2.
- Component 3 (legacy path removal — file, `todaySummary` field, tests): Tasks 3 + 4.
- State-flow requirements (live `@ObservedObject`, `@Environment(\.dismiss)` chain): Task 1 code block plus the wrapper responsibilities documented in the file's own doc comment.
- Manual verification described in the spec's Testing section: Task 2 Step 3.
- Risk item on FloatingPanel z-order: covered by Task 2 Step 3 sub-step 6.
- Risk item on region change while popup open: handled by `WeatherDetailPopup`'s existing `.onChange(of: display)`; no plan action needed, spec explicitly notes it.

No spec requirement is left without a task.

**Placeholder scan**

Every code step contains the exact code to be written or deleted. No "TBD" / "similar to Task N" / "handle edge cases" / "add appropriate error handling" markers.

**Type consistency**

- `WeatherDetailPopupHost` signature is `init(viewModel: MapViewModel)` in both the definition (Task 1) and the call site (Task 2).
- `MapViewController.viewModel` matches — declared as `let viewModel: MapViewModel` at `MapViewController.swift:67`.
- `viewModel.weatherDisplay` is `@Published var weatherDisplay: WeatherDisplay?` on `MapViewModel` — the wrapper passes it to `WeatherDetailPopup(display:isPresented:)` which takes `display: WeatherDisplay?` (see `WeatherDetailPopup.swift:23`). Types line up.
- After Task 3, `WeatherDisplay` no longer has `todaySummary` — Task 4 removes the last test reference in the same PR, so no cross-task type mismatch survives.

Plan is internally consistent.
