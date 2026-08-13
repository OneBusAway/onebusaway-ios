# More Floating Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-trailing floating "More" button on `MapPanelRootView` that routes through the existing sheet coordinator to a `UIViewControllerRepresentable` hosting the current UIKit `MoreViewController` inside a `UINavigationController`.

**Architecture:** Push `AppSheetRoute.more` from the button's action; `AppSheetViewFactory` returns a new `MoreSheetHost` (`UIViewControllerRepresentable`) that wraps `UINavigationController(rootViewController: MoreViewController(application:))`. Introduce a `regularGlassEffectIfAvailable(in:)` view modifier so the button matches the WeatherButton style from #1166 across iOS 26+ and pre-26.

**Tech Stack:** Swift 5, SwiftUI, UIKit interop via `UIViewControllerRepresentable`, XCTest + Nimble for unit tests, XcodeGen for project generation, xcodebuild for CI-shaped builds/tests.

**Spec:** [docs/superpowers/specs/2026-07-02-more-floating-button-design.md](../specs/2026-07-02-more-floating-button-design.md)

## Global Constraints

- **Branch:** `feature/more-floating-button`.
- **Target iOS version:** 17.0+ (Swift 5.3+). Any iOS 26 API must be feature-gated via `#available(iOS 26.0, *)`.
- **Frameworks:** Product code goes in `OBAKit` (UI). Do **not** touch `OBAKitCore` (extension-safe core).
- **No changes to `MoreViewController` itself.** The wrapper exists to keep it untouched.
- **No new feature flag.** The button appears whenever `MapPanelRootView` renders (which is itself gated by `FeatureFlags.useMapPanelExperienceKey`).
- **Regenerate project after adding files:** run `scripts/generate_project OneBusAway` after any file add/rename before building.
- **No auto-commits.** Individual commit steps in this plan are guidance; the human operator will decide when to stage/commit (per the "no auto commit" user preference).
- **Commit messages:** one-line subjects, no `Co-Authored-By: Claude` trailer (per project git conventions).

---

## File Structure

**New files:**

- `OBAKit/Sheet/Root/MoreButton.swift` — SwiftUI floating button rendered in the `MapPanelRootView` top-trailing overlay slot.
- `OBAKit/Sheet/Root/MoreSheetHost.swift` — `UIViewControllerRepresentable` wrapping `UINavigationController(rootViewController: MoreViewController(application:))`.
- `OBAKitTests/Sheet/MoreSheetHostTests.swift` — XCTest verifying `makeUIViewController` returns a `UINavigationController` whose `topViewController` is a `MoreViewController`.
- `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift` — XCTest verifying `AppSheetViewFactory.view(for: .more)` renders a `MoreSheetHost` rather than falling through to `unimplementedView`.

**Modified files:**

- `OBAKit/Extensions/SwiftUIExtensions.swift` — add `regularGlassEffectIfAvailable(in:)` view modifier.
- `OBAKit/Sheet/DI/AppSheetViewFactory.swift` — split `.more` out of the shared `unimplementedView` branch; add `moreView()` builder.
- `OBAKit/Sheet/Root/MapPanelRootView.swift` — add `.overlay(alignment: .topTrailing) { moreButton }` and its computed view.

**Unchanged (called out explicitly):**

- `OBAKit/Settings/MoreViewController.swift` — no edits.
- `OBAKit/Sheet/Coordinator/SheetRoute.swift` — `.more` case, detent config, `prefersStacking` already correct.
- `OBAKit/Sheet/Coordinator/SheetCoordinator.swift` — no changes.

---

## Task 1: Add `regularGlassEffectIfAvailable` view modifier

**Files:**
- Modify: `OBAKit/Extensions/SwiftUIExtensions.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  public extension View {
      func regularGlassEffectIfAvailable(in shape: some Shape = Capsule()) -> some View
  }
  ```

**Rationale:** `MoreButton` (Task 3) and (later) `WeatherButton` from #1166 both need iOS 26 Liquid Glass with a `.regularMaterial` fallback. Introducing the modifier here matches #1166's signature verbatim so a post-merge collision is a trivial "keep one copy" resolution.

- [ ] **Step 1: Extend `SwiftUIExtensions.swift` with the modifier**

Append below the existing `FirstAppear` block:

```swift
// MARK: - glassEffectIfAvailable

public extension View {
    /// Applies the iOS 26+ Liquid Glass effect when available, falling back to
    /// `.regularMaterial` on older systems. Handles the surface fill itself —
    /// call sites do not need to add a background.
    @ViewBuilder
    func regularGlassEffectIfAvailable(in shape: some Shape = Capsule()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
```

- [ ] **Step 2: Verify the OBAKit target still builds**

Run:
```bash
scripts/generate_project OneBusAway
xcodebuild build -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```
Expected: `** BUILD SUCCEEDED **`. No new warnings.

- [ ] **Step 3: (Optional) Commit — only if the user asks**

```bash
git add OBAKit/Extensions/SwiftUIExtensions.swift
git commit -m "Add regularGlassEffectIfAvailable view modifier"
```

---

## Task 2: Add `MoreSheetHost` with failing tests

**Files:**
- Create: `OBAKit/Sheet/Root/MoreSheetHost.swift`
- Create: `OBAKitTests/Sheet/MoreSheetHostTests.swift`

**Interfaces:**
- Consumes: `Application` (from `OBAKitCore`), `MoreViewController` (from `OBAKit/Settings/`).
- Produces:
  ```swift
  struct MoreSheetHost: UIViewControllerRepresentable {
      let application: Application
      func makeUIViewController(context: Context) -> UINavigationController
      func updateUIViewController(_ uiViewController: UINavigationController, context: Context)
  }
  ```

- [ ] **Step 1: Write the failing test file**

Create `OBAKitTests/Sheet/MoreSheetHostTests.swift`:

```swift
//
//  MoreSheetHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import SwiftUI
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Smoke-tests for the UIKit wiring wrapper around `MoreViewController`.
/// The wrapping is the entire product surface of `MoreSheetHost`, so these
/// tests exercise the representable by embedding it in a `UIHostingController`
/// and inspecting the resulting child controller.
final class MoreSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    /// `OBATestCase` doesn't own an `Application`; tests build one per-case,
    /// mirroring the pattern in `MapPanelViewModelTests`. Only the pieces
    /// `MoreViewController.init` actually reaches for (regions service,
    /// analytics, user defaults) need to be real — everything else can rely
    /// on the standard stubs.
    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    @MainActor
    func test_makeUIViewController_returnsNavigationControllerWrappingMoreViewController() {
        let dataLoader = MockDataLoader(testName: name)
        let application = createApplication(dataLoader: dataLoader)

        let host = MoreSheetHost(application: application)

        // The Context type is opaque and not user-constructable outside a real
        // SwiftUI update pass, so we drive `makeUIViewController` via a
        // throwaway UIHostingController.
        let probe = UIHostingController(rootView: host)
        _ = probe.view // force the SwiftUI view body to load, which invokes makeUIViewController.

        // Walk the child hierarchy to find the wrapped nav controller.
        let nav = probe.children.compactMap { $0 as? UINavigationController }.first
        expect(nav).toNot(beNil())
        expect(nav?.topViewController).to(beAKindOf(MoreViewController.self))
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new test file is picked up**

```bash
scripts/generate_project OneBusAway
```

Expected: no errors from XcodeGen; `OBAKit.xcodeproj` regenerated.

- [ ] **Step 3: Run the test and confirm it fails to compile**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/MoreSheetHostTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: build failure — `cannot find 'MoreSheetHost' in scope`.

- [ ] **Step 4: Create `MoreSheetHost.swift`**

Create `OBAKit/Sheet/Root/MoreSheetHost.swift`:

```swift
//
//  MoreSheetHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit wiring wrapper: presents the existing `MoreViewController` inside
/// a `UINavigationController` so its `navigationItem` bar buttons render
/// correctly when reached via `AppSheetRoute.more`.
///
/// Deliberately minimal — a future SwiftUI `MoreView` will replace this
/// wrapper in `AppSheetViewFactory` without touching the coordinator or
/// route enum.
struct MoreSheetHost: UIViewControllerRepresentable {
    let application: Application

    func makeUIViewController(context: Context) -> UINavigationController {
        let more = MoreViewController(application: application)
        return UINavigationController(rootViewController: more)
    }

    // `MoreViewController` reads `application` and its stores directly, so
    // nothing SwiftUI-side changes over the sheet's lifetime.
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) { }
}
```

- [ ] **Step 5: Regenerate the project (new source file)**

```bash
scripts/generate_project OneBusAway
```

- [ ] **Step 6: Re-run the test — expect it to pass**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/MoreSheetHostTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `Test Suite 'MoreSheetHostTests' passed`.

- [ ] **Step 7: (Optional) Commit — only if the user asks**

```bash
git add OBAKit/Sheet/Root/MoreSheetHost.swift OBAKitTests/Sheet/MoreSheetHostTests.swift
git commit -m "Add MoreSheetHost representable and smoke tests"
```

---

## Task 3: Add `MoreButton` SwiftUI view

**Files:**
- Create: `OBAKit/Sheet/Root/MoreButton.swift`

**Interfaces:**
- Consumes: `regularGlassEffectIfAvailable(in:)` (Task 1), `ThemeMetrics.controllerMargin` (already `20.0` in `OBAKitCore/Theme/Theme.swift`).
- Produces:
  ```swift
  struct MoreButton: View {
      let action: () -> Void
  }
  ```

**Rationale:** pure presentational button — no unit test. Snapshot testing isn't part of the project's suite; the build compiling and manual verification in Task 5 cover it.

- [ ] **Step 1: Create `MoreButton.swift`**

Create `OBAKit/Sheet/Root/MoreButton.swift`:

```swift
//
//  MoreButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating capsule button rendered in the top-trailing overlay slot of
/// `MapPanelRootView`. Tapping it pushes `AppSheetRoute.more` onto the
/// sheet coordinator; the button itself is pure presentation.
struct MoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .regularGlassEffectIfAvailable(in: Capsule())
        .accessibilityLabel(Text(OBALoc(
            "more_controller.title",
            value: "More",
            comment: "Title of the More tab / accessibility label for the map-panel more button."
        )))
    }
}
```

- [ ] **Step 2: Regenerate the project**

```bash
scripts/generate_project OneBusAway
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: (Optional) Commit — only if the user asks**

```bash
git add OBAKit/Sheet/Root/MoreButton.swift
git commit -m "Add MoreButton SwiftUI view for map-panel top-trailing slot"
```

---

## Task 4: Route `.more` through `AppSheetViewFactory.moreView()`

**Files:**
- Modify: `OBAKit/Sheet/DI/AppSheetViewFactory.swift`
- Create: `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`

**Interfaces:**
- Consumes: `MoreSheetHost(application:)` (Task 2).
- Produces:
  ```swift
  extension AppSheetViewFactory {
      func moreView() -> MoreSheetHost
  }
  ```
  and swaps the `.more` case out of the shared `unimplementedView` branch inside `view(for:)`.

- [ ] **Step 1: Write the failing factory test**

Create `OBAKitTests/Sheet/AppSheetViewFactoryTests.swift`:

```swift
//
//  AppSheetViewFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import SwiftUI
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Per-route factory branch coverage. Each branch that's been "wired up"
/// (i.e. removed from the shared `unimplementedView` catch-all) gets a
/// dedicated test so a future refactor that accidentally drops the branch
/// back into the catch-all fails the suite.
final class AppSheetViewFactoryTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    @MainActor
    func test_view_forMore_returnsMoreSheetHost() {
        let dataLoader = MockDataLoader(testName: name)
        let application = createApplication(dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application)
        let host = UIHostingController(rootView: factory.view(for: .more))
        _ = host.view // force the view body to evaluate.

        // `MoreSheetHost` embeds a UINavigationController; walk the child
        // hierarchy to confirm it landed rather than the placeholder Text
        // from `unimplementedView`.
        let nav = host.children.compactMap { $0 as? UINavigationController }.first
        expect(nav).toNot(beNil())
        expect(nav?.topViewController).to(beAKindOf(MoreViewController.self))
    }
}
```

- [ ] **Step 2: Regenerate the project**

```bash
scripts/generate_project OneBusAway
```

- [ ] **Step 3: Run the failing test**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/AppSheetViewFactoryTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: **DEBUG builds** — the test *may* crash inside `assertionFailure("AppSheetRoute.more has no view registered yet.")` from `unimplementedView`. That's still an acceptable "failing" signal for TDD; if the assertion aborts the process, the test will be reported as a failure by xcodebuild.

If the assertion halts the test runner in a way that prevents the next task from proceeding, temporarily edit the assertion to just `Logger.error(...)` — but the preferred path is to move straight to Step 4 and land the real branch.

- [ ] **Step 4: Update `AppSheetViewFactory.swift` — split `.more` out and add `moreView()`**

In `OBAKit/Sheet/DI/AppSheetViewFactory.swift`:

Replace the `view(for:)` switch body:

```swift
    @ViewBuilder
    func view(for route: AppSheetRoute) -> some View {
        switch route {
        case .home:
            homeView()
        case .more:
            moreView()
        // Wiring a push for one of these routes before its view exists will
        // trip the debug assertion in `unimplementedView(for:)` — register the
        // view here before reaching for `SheetCoordinator.push(...)`.
        //
        // TODO: `.search` is base-layer and has `isDismissDisabled: true`
        // — its real view needs to wire up an explicit back affordance
        // (the home sheet only knows how to push, not pop), otherwise the
        // route is unreachable once entered.
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .routePicker,
             .currentTrip, .transitAlert, .settings:
            unimplementedView(for: route)
        }
    }
```

Below `homeView()`, add:

```swift
    /// Bridges `AppSheetRoute.more` to the existing UIKit `MoreViewController`
    /// via `MoreSheetHost`. Swap this branch's return type once the SwiftUI
    /// `MoreView` lands.
    func moreView() -> MoreSheetHost {
        MoreSheetHost(application: application)
    }
```

- [ ] **Step 5: Regenerate and re-run**

```bash
scripts/generate_project OneBusAway
xcodebuild test-without-building \
  -only-testing:OBAKitTests/AppSheetViewFactoryTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `Test Suite 'AppSheetViewFactoryTests' passed`.

- [ ] **Step 6: Run the wider Sheet test suite to catch regressions**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests/AppSheetRouteTests \
  -only-testing:OBAKitTests/SheetCoordinatorTests \
  -only-testing:OBAKitTests/MoreSheetHostTests \
  -only-testing:OBAKitTests/AppSheetViewFactoryTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all four suites pass.

- [ ] **Step 7: (Optional) Commit — only if the user asks**

```bash
git add OBAKit/Sheet/DI/AppSheetViewFactory.swift OBAKitTests/Sheet/AppSheetViewFactoryTests.swift
git commit -m "Route AppSheetRoute.more through MoreSheetHost factory branch"
```

---

## Task 5: Wire the top-trailing overlay in `MapPanelRootView`

**Files:**
- Modify: `OBAKit/Sheet/Root/MapPanelRootView.swift`

**Interfaces:**
- Consumes: `MoreButton(action:)` (Task 3), `SheetCoordinator<AppSheetRoute>.push(_:)` (existing), `AppSheetRoute.more` (existing).
- Produces: no new symbols; strictly additive to the view body.

- [ ] **Step 1: Update `MapPanelRootView.swift`**

Change the body from:

```swift
    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .floatingSheet(coordinator: coordinator) { route in
            factory.view(for: route)
        }
    }
```

to:

```swift
    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        // TODO: Detent-aware bottom padding. Pinned to the collapsed sheet
        // height today, so dragging the sheet up to `.medium` or
        // `largeDetent` lets the user-location annotation and any future map
        // overlays slip under the sheet.
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .overlay(alignment: .topTrailing) {
            moreButton
        }
        .floatingSheet(coordinator: coordinator) { route in
            factory.view(for: route)
        }
    }

    private var moreButton: some View {
        MoreButton {
            coordinator.push(.more)
        }
        .padding(ThemeMetrics.controllerMargin)
    }
```

- [ ] **Step 2: Regenerate and build**

```bash
scripts/generate_project OneBusAway
xcodebuild build -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full unit-test target**

```bash
xcodebuild test-without-building \
  -only-testing:OBAKitTests \
  -project 'OBAKit.xcodeproj' -scheme 'App' \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: all suites pass. If any suite unrelated to this feature fails, hand back — do not proceed to manual verification with a red suite.

- [ ] **Step 4: Manual verification (required — this is a UI change)**

Boot the app on an iPhone 16 simulator with the map-panel experience flag enabled. The flag lives in `FeatureFlags.useMapPanelExperienceKey` and is toggled from **Settings → Experimental** (`SettingsViewController`), or by seeding `UserDefaults` before launch.

Verify:

1. A capsule "line.3.horizontal" button appears in the map's top-trailing corner (below the safe area, matching `ThemeMetrics.controllerMargin` inset).
2. Tapping the button presents a sheet stacked over the home sheet, initial detent `.large`.
3. The presented sheet's navigation bar shows **Contact Us** on the left and **Settings** on the right; both bar buttons activate their existing flows.
4. Dragging the sheet down dismisses it cleanly; no orphaned VC state (verify by tapping the button again — the presented content is fresh).
5. On iOS 26+ the button renders with Liquid Glass; on iOS 17–18 it renders with `.regularMaterial` — no visual glitches.
6. VoiceOver announces the button as "More".

Attach screenshots (or a short screen recording) to the PR description.

- [ ] **Step 5: SwiftLint**

```bash
scripts/swiftlint.sh
```

Expected: no new warnings introduced by this change.

- [ ] **Step 6: (Optional) Commit — only if the user asks**

```bash
git add OBAKit/Sheet/Root/MapPanelRootView.swift
git commit -m "Wire top-trailing More button overlay on MapPanelRootView"
```

---

## Self-Review Checklist (post-implementation)

Before opening a PR, walk this list once:

- [ ] `MoreViewController.swift` is untouched (`git diff main -- OBAKit/Settings/MoreViewController.swift` is empty).
- [ ] `AppSheetRoute` enum is untouched (`git diff main -- OBAKit/Sheet/Coordinator/SheetRoute.swift` is empty).
- [ ] `regularGlassEffectIfAvailable` is the only new modifier in `SwiftUIExtensions.swift` — no unrelated cleanup.
- [ ] `MapPanelRootView.body` gains only the `.overlay(alignment: .topTrailing)` line and a `moreButton` computed view — no other refactoring.
- [ ] Tests: `MoreSheetHostTests`, `AppSheetViewFactoryTests`, and the pre-existing `AppSheetRouteTests` all pass.
- [ ] Manual verification steps in Task 5 Step 4 are attached to the PR (screenshot or short clip).
- [ ] No commit contains a `Co-Authored-By: Claude` trailer.

---

## Rollback

If the feature needs to be reverted post-merge, the following order is safe:

1. Revert the `MapPanelRootView` overlay diff — the button disappears; nothing else regresses (the map + sheet still work).
2. Revert `AppSheetViewFactory.moreView()` and put `.more` back in the shared `unimplementedView` catch-all — `push(.more)` again renders the placeholder.
3. Delete `MoreSheetHost.swift`, `MoreButton.swift`, and the two new test files.
4. Revert `regularGlassEffectIfAvailable` from `SwiftUIExtensions.swift` — only necessary if #1166 hasn't landed by then; otherwise it's shared with the WeatherButton and must stay.
