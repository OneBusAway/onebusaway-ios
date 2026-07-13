# Stop Page Rethink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Stop screen as a SwiftUI page with two list modes (Chronological / By route), an inline trip-detail panel with a live approach timeline, and one-tap Obaco alarms — shipped behind a default-ON flag alongside the existing `StopViewController`.

**Architecture:** A new `StopPageViewController` (thin `UIHostingController`) hosts `StopPageView`, which is the *only* view observing the existing `StopViewModel` (all subviews take plain values). Pure presentation logic (`DepartureStatus`, list transforms, alarm clamp, approach slice) lives in small value types unit-tested in `OBAKitTests`. The router picks new vs. old screen by feature flag.

**Tech Stack:** Swift / SwiftUI (iOS 18.0), existing `StopViewModel` (Combine `ObservableObject`), `OBAListView`-free, Obaco server-push alarms, XcodeGen project generation, Nimble-free plain XCTest for new tests.

**Spec:** `docs/superpowers/specs/2026-07-10-stop-page-rethink-design.md` — read it before starting. Section references (§4.1 etc.) are to the brief nuances embedded in that spec.

## Global Constraints

- **Deployment target: iOS 18.0** (`Apps/Shared/app_shared.yml`). Do not use iOS 26-only API (e.g. `LazyVStack` swipe actions).
- **Regenerate the project after adding/removing files**: `scripts/generate_project OneBusAway` (XcodeGen; new files are invisible to the build until you do).
- **Build/test commands** (iPhone 17 simulator — iPhone 16 is NOT installed):
  - Build for testing: `xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
  - Run one test class: `xcodebuild test-without-building -only-testing:OBAKitTests/<ClassName> -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
  - Known issue: under Xcode 27 the local test *runner* can crash with a UIScene-lifecycle error after tests build. If that happens, `TEST BUILD SUCCEEDED` plus the compile of the test target is the local bar — say so honestly, never claim tests passed if the runner crashed.
- **Only `StopPageView` observes the view model.** Subviews receive plain values (`let` properties). Never pass the `StopViewModel` into a subview.
- **`ForEach`/`List` identity**: key on `ArrivalDeparture.id` (a `String`). Never `id: \.self` on `ArrivalDeparture`.
- **Rows are unary**: one root `HStack`/`VStack` per row; conditional content goes *inside* it. No `AnyView`, no top-level `if`/`switch` as the row root.
- **Colors**: bridge `UIColor` with `Color(uiColor:)` (never soft-deprecated `Color(_:)`). Status palette from `ThemeColors.shared` — early = red, late = blue, on-time = green, no-real-time = gray (`.secondaryLabel`). Route color (`route.color`) is used ONLY for the route badge and grouped-card stripe.
- **Real-time hard gate (§4.1)**: when `!predicted` — clock glyph, gray countdown, occupancy hidden, "schedule data" label, no approach timeline.
- **User-facing strings** use `OBALoc("key", value:comment:)` like the rest of OBAKit.
- **Reduce Motion**: read `@Environment(\.accessibilityReduceMotion)`; all pulse/wave animations must have a static fallback.
- New UI files go in `OBAKit/Stops/StopPage/`. `OBAKitCore` must stay application-extension-safe (no view controllers there; `UIColor` is fine).
- Run `scripts/swiftlint.sh` before each commit.
- Commit after every task (small, descriptive commits).

---

## File Map

| File | Responsibility |
|---|---|
| `OBAKitCore/Orchestration/FeatureFlags.swift` (modify) | add `useNewStopPageKey` + default-ON resolution helper |
| `OBAKit/ViewRouting/Router.swift` (modify) | branch stop navigation on the flag |
| `OBAKit/Settings/SettingsViewController.swift` (modify) | Experimental toggle row; default-alarm-lead-time row |
| `OBAKitCore/Models/UserData/UserDataStore.swift` (modify) | `defaultAlarmLeadTimeMinutes` setting |
| `OBAKit/ViewModels/StopViewModel.swift` (modify) | walk time, alarm index/set/cancel/change, approach fetch |
| `OBAKit/Stops/StopPage/StopPageViewController.swift` | hosting shell, nav items, Previewable |
| `OBAKit/Stops/StopPage/StopPageView.swift` | root List; sole VM observer |
| `OBAKit/Stops/StopPage/StopPageHeaderView.swift` | map card + walk chip |
| `OBAKit/Stops/StopPage/Departures/ChronologicalListView.swift` | past block, walk partition, rows |
| `OBAKit/Stops/StopPage/Departures/GroupedListView.swift` | route cards |
| `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift` | shared row |
| `OBAKit/Stops/StopPage/Shared/DepartureStatus.swift` | status color/label/gate |
| `OBAKit/Stops/StopPage/Shared/StopPageListBuilder.swift` | partition + grouping transforms |
| `OBAKit/Stops/StopPage/Shared/AlarmLeadTime.swift` | lead-time clamp |
| `OBAKit/Stops/StopPage/Shared/WalkTimeInfo.swift` | walk time computation |
| `OBAKit/Stops/StopPage/Shared/RealtimeGlyph.swift`, `CountdownView.swift`, `RouteBadgeView.swift`, `WalkLineDivider.swift` | shared leaf views |
| `OBAKit/Stops/StopPage/TripPanel/TripDetailPanelView.swift`, `ApproachTimelineView.swift`, `AlarmControlView.swift`, `ApproachSlice.swift` | trip panel |
| `OBAKitTests/Stops/StopPage/*` | unit tests for all pure logic |

---

### Task 1: Feature flag, router branch, hosting shell

**Files:**
- Modify: `OBAKitCore/Orchestration/FeatureFlags.swift`
- Modify: `OBAKit/ViewRouting/Router.swift:87-99`
- Modify: `OBAKit/Settings/SettingsViewController.swift` (~line 58 values dict, ~129 save, ~174 experimental section)
- Create: `OBAKit/Stops/StopPage/StopPageViewController.swift`
- Create: `OBAKit/Stops/StopPage/StopPageView.swift`
- Test: `OBAKitTests/Stops/StopPage/FeatureFlagsTests.swift`

**Interfaces:**
- Produces: `FeatureFlags.useNewStopPageKey: String`, `FeatureFlags.isNewStopPageEnabled(userDefaults:) -> Bool` (default true), `StopPageViewController(application:stopID:)` / `(application:stop:)` with `bookmarkContext`/`transferContext` vars, `StopPageView(viewModel:)` placeholder.
- Consumes: existing `StopViewModel(application:stopID:stop:bookmarkContext:transferContext:)`, `Router.navigateTo(stop:from:bookmark:transferContext:)`.

- [ ] **Step 1: Write the failing test**

```swift
// OBAKitTests/Stops/StopPage/FeatureFlagsTests.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//
import XCTest
@testable import OBAKitCore

final class FeatureFlagsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FeatureFlagsTests")!
        defaults.removePersistentDomain(forName: "FeatureFlagsTests")
    }

    func test_newStopPage_defaultsToEnabled() {
        XCTAssertTrue(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    func test_newStopPage_respectsExplicitFalse() {
        defaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        XCTAssertFalse(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }

    func test_newStopPage_respectsExplicitTrue() {
        defaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
        XCTAssertTrue(FeatureFlags.isNewStopPageEnabled(userDefaults: defaults))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: compile FAILURE — `isNewStopPageEnabled` / `useNewStopPageKey` not found.

- [ ] **Step 3: Implement flag + helper**

In `OBAKitCore/Orchestration/FeatureFlags.swift`, add to the enum:

```swift
    /// Gates the redesigned SwiftUI Stop page over the classic
    /// `StopViewController`. Enabled by default; the Settings > Experimental
    /// toggle writes an explicit value.
    public static let useNewStopPageKey = "OBAUseNewStopPage"

    /// Resolves the new-stop-page flag, defaulting to enabled when the user
    /// has never touched the toggle.
    public static func isNewStopPageEnabled(userDefaults: UserDefaults) -> Bool {
        userDefaults.object(forKey: useNewStopPageKey) as? Bool ?? true
    }
```

- [ ] **Step 4: Create the hosting shell and placeholder view**

`OBAKit/Stops/StopPage/StopPageView.swift`:

```swift
//
//  StopPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Root view of the redesigned Stop page. This is the ONLY view that observes
/// `StopViewModel`; every subview receives plain values so the VM's frequent
/// `@Published` churn (refresh + status timers) re-evaluates one shallow body.
struct StopPageView: View {
    @ObservedObject var viewModel: StopViewModel

    var body: some View {
        List {
            Section {
                Text(viewModel.stop?.name ?? "…")
            }
        }
        .listStyle(.insetGrouped)
        .task { await viewModel.start() }
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
    }
}
```

`OBAKit/Stops/StopPage/StopPageViewController.swift`:

```swift
//
//  StopPageViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// Hosting shell for the redesigned SwiftUI Stop page. Owns UIKit-side chrome
/// (nav bar items, menus) and keeps parity entry points (`Previewable` etc.)
/// working while `FeatureFlags.useNewStopPageKey` is enabled.
class StopPageViewController: UIHostingController<StopPageView>, AppContext {
    let application: Application
    let viewModel: StopViewModel

    var bookmarkContext: Bookmark? {
        get { viewModel.bookmarkContext }
        set { viewModel.bookmarkContext = newValue }
    }

    var transferContext: TransferContext? {
        get { viewModel.transferContext }
        set { viewModel.transferContext = newValue }
    }

    convenience init(application: Application, stop: Stop) {
        self.init(application: application, stopID: stop.id, stop: stop)
    }

    convenience init(application: Application, stopID: StopID) {
        self.init(application: application, stopID: stopID, stop: nil)
    }

    private init(application: Application, stopID: StopID, stop: Stop?) {
        self.application = application
        self.viewModel = StopViewModel(application: application, stopID: stopID, stop: stop)
        super.init(rootView: StopPageView(viewModel: viewModel))
        hidesBottomBarWhenPushed = false
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.stop.map(Formatters.formattedTitle(stop:)) ?? Strings.loading
        navigationItem.largeTitleDisplayMode = .never
    }
}
```

Note: if `AppContext` requires more than an `application` property, check `OBAKit/Orchestration/AppContext.swift` and conform minimally; if conformance drags in unwanted requirements, drop the protocol — nothing in this task needs it. If `Strings.loading` doesn't exist, use `OBALoc("stop_page_controller.loading", value: "Loading…", comment: "Stop page placeholder title while the stop loads")`.

- [ ] **Step 5: Branch the router**

In `OBAKit/ViewRouting/Router.swift`, replace the bodies of `navigateTo(stop:...)` and `navigateTo(stopID:)`:

```swift
    public func navigateTo(stop: Stop, from fromController: UIViewController, bookmark: Bookmark? = nil, transferContext: TransferContext? = nil) {
        guard shouldNavigate(from: fromController, to: .stop(stop)) else { return }
        if FeatureFlags.isNewStopPageEnabled(userDefaults: application.userDefaults) {
            let stopController = StopPageViewController(application: application, stop: stop)
            stopController.bookmarkContext = bookmark
            stopController.transferContext = transferContext
            navigate(to: stopController, from: fromController)
        } else {
            let stopController = StopViewController(application: application, stop: stop)
            stopController.bookmarkContext = bookmark
            stopController.transferContext = transferContext
            navigate(to: stopController, from: fromController)
        }
    }

    public func navigateTo(stopID: StopID, from fromController: UIViewController) {
        guard shouldNavigate(from: fromController, to: .stopID(stopID)) else { return }
        if FeatureFlags.isNewStopPageEnabled(userDefaults: application.userDefaults) {
            navigate(to: StopPageViewController(application: application, stopID: stopID), from: fromController)
        } else {
            navigate(to: StopViewController(application: application, stopID: stopID), from: fromController)
        }
    }
```

Check `StopViewModel.bookmarkContext`/`transferContext` are settable (`var` — they are, `StopViewModel.swift:95-98`).

- [ ] **Step 6: Settings toggle**

In `OBAKit/Settings/SettingsViewController.swift`:
- In the values dictionary near line 58 (alongside `FeatureFlags.useMapPanelExperienceKey`), add:
  ```swift
  FeatureFlags.useNewStopPageKey: FeatureFlags.isNewStopPageEnabled(userDefaults: application.userDefaults),
  ```
- In `saveExperimentalValues(_:)` (~line 129), add:
  ```swift
  if let useNewStopPage = values[FeatureFlags.useNewStopPageKey] as? Bool {
      application.userDefaults.set(useNewStopPage, forKey: FeatureFlags.useNewStopPageKey)
  }
  ```
- In `experimentalSection` (~line 176), add a row after the map-panel row:
  ```swift
  section <<< SwitchRow {
      $0.tag = FeatureFlags.useNewStopPageKey
      $0.title = OBALoc("settings_controller.experimental_section.new_stop_page", value: "Use new stop page", comment: "Settings > Experimental section > New stop page toggle")
  }
  ```

- [ ] **Step 7: Regenerate, build, run tests**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests/FeatureFlagsTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED; 3 tests pass (or runner crashes with known UIScene issue — then TEST BUILD SUCCEEDED is the bar).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Add new-stop-page feature flag, router branch, and SwiftUI hosting shell"
```

---

### Task 2: DepartureStatus (the §4.1 gate)

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/DepartureStatus.swift`
- Test: `OBAKitTests/Stops/StopPage/DepartureStatusTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct DepartureStatus {
      let isRealTime: Bool
      let scheduleStatus: ScheduleStatus
      let deviationMinutes: Int
      init(arrivalDeparture: ArrivalDeparture)
      init(isRealTime: Bool, scheduleStatus: ScheduleStatus, deviationMinutes: Int) // test seam
      var color: UIColor          // status palette; .secondaryLabel when !isRealTime
      var label: String           // "on time" / "3 min late" / "3 min early" / "schedule data"
      var showsOccupancy: Bool    // == isRealTime
      var accessibilityStatusDescription: String // "live, on time" / "scheduled time only, no live data"
  }
  ```
- Consumes: `ScheduleStatus` (OBAKitCore), `ThemeColors.shared`, `ArrivalDeparture.predicted/.scheduleStatus/.deviationFromScheduleInMinutes`.

- [ ] **Step 1: Write the failing tests**

```swift
// OBAKitTests/Stops/StopPage/DepartureStatusTests.swift
import XCTest
import OBAKitCore
@testable import OBAKit

final class DepartureStatusTests: XCTestCase {

    func test_scheduledOnly_isGrayWithScheduleDataLabel() {
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        XCTAssertEqual(status.color, UIColor.secondaryLabel)
        XCTAssertEqual(status.label, "schedule data")
        XCTAssertFalse(status.showsOccupancy)
    }

    func test_scheduledOnly_neverClaimsOnTime_evenWithZeroDeviation() {
        // §4.1: a scheduled bus is NOT "on time" — we have no idea if it's on time.
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        XCTAssertNotEqual(status.label, "on time")
    }

    func test_onTime_isGreen() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        XCTAssertEqual(status.color, ThemeColors.shared.departureOnTime)
        XCTAssertEqual(status.label, "on time")
        XCTAssertTrue(status.showsOccupancy)
    }

    func test_late_isBlue_withMinuteCount() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 4)
        XCTAssertEqual(status.color, ThemeColors.shared.departureLate)
        XCTAssertEqual(status.label, "4 min late")
    }

    func test_early_isRed_withMinuteCount() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .early, deviationMinutes: -3)
        XCTAssertEqual(status.color, ThemeColors.shared.departureEarly)
        XCTAssertEqual(status.label, "3 min early")
    }
}
```

- [ ] **Step 2: Build to verify tests fail**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: compile FAILURE — `DepartureStatus` not found.

- [ ] **Step 3: Implement**

```swift
// OBAKit/Stops/StopPage/Shared/DepartureStatus.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The single home of the Stop page's status visual language: countdowns,
/// adherence labels, and the real-time hard gate. When `isRealTime == false`
/// the UI must show a clock glyph, gray text, no occupancy, and never claim
/// the trip is "on time" — a scheduled bus's punctuality is unknown.
struct DepartureStatus {
    let isRealTime: Bool
    let scheduleStatus: ScheduleStatus
    let deviationMinutes: Int

    init(arrivalDeparture: ArrivalDeparture) {
        self.init(
            isRealTime: arrivalDeparture.predicted,
            scheduleStatus: arrivalDeparture.scheduleStatus,
            deviationMinutes: arrivalDeparture.deviationFromScheduleInMinutes
        )
    }

    init(isRealTime: Bool, scheduleStatus: ScheduleStatus, deviationMinutes: Int) {
        self.isRealTime = isRealTime
        self.scheduleStatus = scheduleStatus
        self.deviationMinutes = deviationMinutes
    }

    var showsOccupancy: Bool { isRealTime }

    var color: UIColor {
        guard isRealTime else { return .secondaryLabel }
        switch scheduleStatus {
        case .onTime: return ThemeColors.shared.departureOnTime
        case .early: return ThemeColors.shared.departureEarly
        case .delayed: return ThemeColors.shared.departureLate
        default: return .secondaryLabel
        }
    }

    var label: String {
        guard isRealTime else {
            return OBALoc("stop_page.status.schedule_data", value: "schedule data", comment: "Adherence label for a departure with no real-time signal; deliberately avoids claiming the bus is on time.")
        }
        switch scheduleStatus {
        case .onTime:
            return OBALoc("stop_page.status.on_time", value: "on time", comment: "Adherence label for an on-time departure")
        case .delayed:
            let fmt = OBALoc("stop_page.status.late_fmt", value: "%d min late", comment: "Adherence label for a late departure. %d is minutes late.")
            return String(format: fmt, abs(deviationMinutes))
        case .early:
            let fmt = OBALoc("stop_page.status.early_fmt", value: "%d min early", comment: "Adherence label for an early departure. %d is minutes early.")
            return String(format: fmt, abs(deviationMinutes))
        default:
            return OBALoc("stop_page.status.schedule_data", value: "schedule data", comment: "Adherence label for a departure with no real-time signal; deliberately avoids claiming the bus is on time.")
        }
    }

    var accessibilityStatusDescription: String {
        if isRealTime {
            let fmt = OBALoc("stop_page.status.a11y_live_fmt", value: "live tracking, %@", comment: "VoiceOver status suffix for a live departure. %@ is the adherence label.")
            return String(format: fmt, label)
        }
        return OBALoc("stop_page.status.a11y_scheduled", value: "scheduled time only, no live data", comment: "VoiceOver status suffix for a schedule-only departure")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests/DepartureStatusTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 5 tests pass (or TEST BUILD SUCCEEDED + known runner crash).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add DepartureStatus: adherence colors, labels, and the real-time hard gate"
```

---

### Task 3: List transforms (partition + grouping)

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/StopPageListBuilder.swift`
- Test: `OBAKitTests/Stops/StopPage/StopPageListBuilderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol DepartureListEntry {
      var id: String { get }
      var routeID: RouteID { get }
      var arrivalDepartureMinutes: Int { get }
      var temporalState: TemporalState { get }
  }
  extension ArrivalDeparture: DepartureListEntry {} // members already exist

  enum StopPageListBuilder {
      struct ChronologicalPartition<D: DepartureListEntry> {
          let past: [D]        // temporalState == .past; dim only (§4.2)
          let missed: [D]      // upcoming but sooner than walk time; dim + strikethrough
          let reachable: [D]
      }
      static func chronologicalPartition<D: DepartureListEntry>(_ departures: [D], walkMinutes: Int?) -> ChronologicalPartition<D>

      struct RouteGroup<D: DepartureListEntry> {
          let routeID: RouteID
          let departures: [D]  // time-sorted; [0] is the "next" header departure
          var next: D { departures[0] }
          var upcoming: [D] { Array(departures.dropFirst()) }
          var chips: [D] { Array(departures.dropFirst().prefix(3)) }
      }
      static func routeGroups<D: DepartureListEntry>(_ departures: [D]) -> [RouteGroup<D>]
  }
  ```
- Consumes: `RouteID` (= `String`), `TemporalState` (OBAKitCore). Hidden-route filtering is NOT done here — callers pre-filter with the existing `Sequence.filter(preferences:)` (`ArrivalDeparture.swift:469`).

- [ ] **Step 1: Write the failing tests**

```swift
// OBAKitTests/Stops/StopPage/StopPageListBuilderTests.swift
import XCTest
import OBAKitCore
@testable import OBAKit

private struct StubDeparture: DepartureListEntry {
    let id: String
    let routeID: RouteID
    let arrivalDepartureMinutes: Int
    var temporalState: TemporalState {
        arrivalDepartureMinutes < 0 ? .past : (arrivalDepartureMinutes == 0 ? .present : .future)
    }
}

private func dep(_ id: String, route: String, mins: Int) -> StubDeparture {
    StubDeparture(id: id, routeID: route, arrivalDepartureMinutes: mins)
}

final class StopPageListBuilderTests: XCTestCase {

    // MARK: - Chronological partition

    func test_partition_splitsAtWalkThreshold() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5), dep("c", route: "62", mins: 7)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        XCTAssertEqual(p.missed.map(\.id), ["a"])       // 1 < 4: can't reach on foot
        XCTAssertEqual(p.reachable.map(\.id), ["b", "c"]) // 5 and 7 >= 4 (§4.5: catchable iff mins >= walk)
        XCTAssertTrue(p.past.isEmpty)
    }

    func test_partition_boundaryIsCatchable() {
        // minutesAway == walkMinutes is catchable (§4.5: >=)
        let p = StopPageListBuilder.chronologicalPartition([dep("x", route: "5", mins: 4)], walkMinutes: 4)
        XCTAssertEqual(p.reachable.map(\.id), ["x"])
        XCTAssertTrue(p.missed.isEmpty)
    }

    func test_partition_nilWalk_hasNoMissedBucket() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        XCTAssertTrue(p.missed.isEmpty)
        XCTAssertEqual(p.reachable.map(\.id), ["a", "b"])
    }

    func test_partition_pastIsSeparateFromMissed() {
        // §4.2: past (already departed) and missed (can't walk there in time) are distinct.
        let deps = [dep("gone", route: "24", mins: -3), dep("miss", route: "H", mins: 1), dep("ok", route: "5", mins: 9)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        XCTAssertEqual(p.past.map(\.id), ["gone"])
        XCTAssertEqual(p.missed.map(\.id), ["miss"])
        XCTAssertEqual(p.reachable.map(\.id), ["ok"])
    }

    func test_partition_sortsByMinutes() {
        let deps = [dep("b", route: "1", mins: 9), dep("a", route: "2", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        XCTAssertEqual(p.reachable.map(\.id), ["a", "b"])
    }

    // MARK: - Route groups

    func test_groups_orderedBySoonestDeparture_notRouteName() {
        // §4.9: route with a bus in 1m outranks a route whose next is 5m.
        let deps = [
            dep("z5", route: "5", mins: 5), dep("h1", route: "H Line", mins: 1),
            dep("h2", route: "H Line", mins: 12), dep("z5b", route: "5", mins: 30)
        ]
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups.map(\.routeID), ["H Line", "5"])
        XCTAssertEqual(groups[0].departures.map(\.id), ["h1", "h2"])
        XCTAssertEqual(groups[0].next.id, "h1")
    }

    func test_groups_excludePastDepartures() {
        let deps = [dep("gone", route: "5", mins: -2), dep("soon", route: "5", mins: 6)]
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].departures.map(\.id), ["soon"])
    }

    func test_groups_chips_areAtMostThree_afterNext() {
        let deps = (0..<6).map { dep("d\($0)", route: "40", mins: 5 + $0 * 5) }
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups[0].chips.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(groups[0].upcoming.count, 5)
    }

    func test_groups_singleDeparture_hasEmptyChips() {
        // Renders as "later trips not loaded" (§4.4) — builder just returns empty.
        let groups = StopPageListBuilder.routeGroups([dep("only", route: "24", mins: 8)])
        XCTAssertTrue(groups[0].chips.isEmpty)
    }
}
```

- [ ] **Step 2: Build to verify failure**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: compile FAILURE.

- [ ] **Step 3: Implement**

```swift
// OBAKit/Stops/StopPage/Shared/StopPageListBuilder.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The list-shape abstraction over `ArrivalDeparture` that the Stop page's
/// pure transforms operate on; production code passes `ArrivalDeparture`,
/// tests pass lightweight stubs (the real type only decodes from JSON).
protocol DepartureListEntry {
    var id: String { get }
    var routeID: RouteID { get }
    var arrivalDepartureMinutes: Int { get }
    var temporalState: TemporalState { get }
}

extension ArrivalDeparture: DepartureListEntry {}

/// Pure transforms shared by both Stop page list modes. Both modes are
/// projections of the same filtered departure list (spec §3); callers apply
/// `filter(preferences:)` for hidden routes before calling in.
enum StopPageListBuilder {

    // MARK: - Chronological

    struct ChronologicalPartition<D: DepartureListEntry> {
        /// Already departed. Rendered dimmed, no strikethrough (§4.2).
        let past: [D]
        /// Upcoming, but arriving sooner than the user can walk to the stop.
        /// Rendered dimmed + struck-through (§4.2).
        let missed: [D]
        /// Catchable on foot: `arrivalDepartureMinutes >= walkMinutes` (§4.5).
        let reachable: [D]
    }

    static func chronologicalPartition<D: DepartureListEntry>(_ departures: [D], walkMinutes: Int?) -> ChronologicalPartition<D> {
        let sorted = departures.sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }
        let past = sorted.filter { $0.temporalState == .past }
        let upcoming = sorted.filter { $0.temporalState != .past }

        guard let walkMinutes else {
            return ChronologicalPartition(past: past, missed: [], reachable: upcoming)
        }

        let missed = upcoming.filter { $0.arrivalDepartureMinutes < walkMinutes }
        let reachable = upcoming.filter { $0.arrivalDepartureMinutes >= walkMinutes }
        return ChronologicalPartition(past: past, missed: missed, reachable: reachable)
    }

    // MARK: - Grouped ("By route")

    struct RouteGroup<D: DepartureListEntry> {
        let routeID: RouteID
        /// Time-sorted; never empty. `[0]` is the card-header "next" departure.
        let departures: [D]

        var next: D { departures[0] }
        var upcoming: [D] { Array(departures.dropFirst()) }
        /// The small status-tinted pills; empty renders "later trips not loaded" (§4.4).
        var chips: [D] { Array(departures.dropFirst().prefix(3)) }
    }

    /// Groups by route, preserving first-appearance order after the time sort,
    /// so routes rank by their soonest departure (§4.9). Past departures are
    /// excluded — grouped mode has no past block.
    static func routeGroups<D: DepartureListEntry>(_ departures: [D]) -> [RouteGroup<D>] {
        let sorted = departures
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureMinutes < $1.arrivalDepartureMinutes }

        var order: [RouteID] = []
        var buckets: [RouteID: [D]] = [:]
        for departure in sorted {
            if buckets[departure.routeID] == nil { order.append(departure.routeID) }
            buckets[departure.routeID, default: []].append(departure)
        }
        return order.map { RouteGroup(routeID: $0, departures: buckets[$0]!) }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests/StopPageListBuilderTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 9 tests pass (or TEST BUILD SUCCEEDED bar).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add StopPageListBuilder: walk-line partition and soonest-first route grouping"
```

---

### Task 4: AlarmLeadTime clamp + WalkTimeInfo + default lead-time setting

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/AlarmLeadTime.swift`
- Create: `OBAKit/Stops/StopPage/Shared/WalkTimeInfo.swift`
- Modify: `OBAKitCore/Models/UserData/UserDataStore.swift` (add `defaultAlarmLeadTimeMinutes`)
- Test: `OBAKitTests/Stops/StopPage/AlarmLeadTimeTests.swift`, `OBAKitTests/Stops/StopPage/WalkTimeInfoTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum AlarmLeadTime {
      static let minimumMinutes = 1
      static let maximumMinutes = 15
      static let defaultMinutes = 5
      /// nil when no valid lead time exists (departure too soon: minutes <= 1)
      static func clamped(_ requested: Int, minutesUntilDeparture: Int) -> Int?
  }
  struct WalkTimeInfo: Equatable {
      let walkMinutes: Int          // rounded UP — never promise a shorter walk
      let distance: CLLocationDistance
      static func compute(from userLocation: CLLocation?, to stopLocation: CLLocation?, speedMetersPerSecond: Double) -> WalkTimeInfo?
      // nil when either location missing, speed <= 0, or distance <= 40m (matches WalkTimeView behavior)
  }
  ```
- Produces on `UserDataStore` (and its protocol if one declares user-defaults settings — follow the pattern of `walkingSpeedMetersPerSecond` in that file): `var defaultAlarmLeadTimeMinutes: Int` (get/set, defaults to 5, UserDefaults-backed with key `"defaultAlarmLeadTimeMinutes"` added to the private keys enum near line 353).
- Consumes: `WalkingSpeed.defaultMetersPerSecond` (exists — see `WalkingDirections.swift:24`).

- [ ] **Step 1: Write the failing tests**

```swift
// OBAKitTests/Stops/StopPage/AlarmLeadTimeTests.swift
import XCTest
@testable import OBAKit

final class AlarmLeadTimeTests: XCTestCase {
    func test_requestWithinRange_passesThrough() {
        XCTAssertEqual(AlarmLeadTime.clamped(5, minutesUntilDeparture: 20), 5)
    }

    func test_clampsToMaximum15() {
        XCTAssertEqual(AlarmLeadTime.clamped(30, minutesUntilDeparture: 60), 15)
    }

    func test_clampsToMinimum1() {
        XCTAssertEqual(AlarmLeadTime.clamped(0, minutesUntilDeparture: 20), 1)
    }

    func test_cappedBelowMinutesUntilDeparture() {
        // A buzz can't be scheduled for a moment that's already passed.
        XCTAssertEqual(AlarmLeadTime.clamped(10, minutesUntilDeparture: 4), 3)
    }

    func test_departureTooSoon_returnsNil() {
        // Matches StopViewModel.canCreateAlarm: requires arrivalDepartureMinutes > 1.
        XCTAssertNil(AlarmLeadTime.clamped(5, minutesUntilDeparture: 1))
        XCTAssertNil(AlarmLeadTime.clamped(5, minutesUntilDeparture: 0))
    }
}
```

```swift
// OBAKitTests/Stops/StopPage/WalkTimeInfoTests.swift
import XCTest
import CoreLocation
@testable import OBAKit

final class WalkTimeInfoTests: XCTestCase {
    // ~111m per 0.001 degree latitude at the equator; use real CLLocations.
    private let stopLocation = CLLocation(latitude: 47.6097, longitude: -122.3331)

    func test_computesMinutesRoundedUp() {
        // ~500m at 1.25 m/s = 400s = 6.67 min -> 7 min
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        let info = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25)
        XCTAssertNotNil(info)
        XCTAssertEqual(info!.walkMinutes, 7)
    }

    func test_nilWhenUserLocationMissing() {
        XCTAssertNil(WalkTimeInfo.compute(from: nil, to: stopLocation, speedMetersPerSecond: 1.25))
    }

    func test_nilWhenVeryClose() {
        // <= 40m: suppress, matching today's WalkTimeView behavior.
        let user = CLLocation(latitude: 47.60972, longitude: -122.3331)
        XCTAssertNil(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25))
    }

    func test_nilWhenSpeedInvalid() {
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        XCTAssertNil(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 0))
    }
}
```

- [ ] **Step 2: Build to verify failure**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: compile FAILURE.

- [ ] **Step 3: Implement**

```swift
// OBAKit/Stops/StopPage/Shared/AlarmLeadTime.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Lead-time rules for departure alarms: user-adjustable within 1–15 minutes,
/// but never scheduled at or past the departure itself.
enum AlarmLeadTime {
    static let minimumMinutes = 1
    static let maximumMinutes = 15
    static let defaultMinutes = 5

    /// Clamps a requested lead time into the valid range for a departure
    /// `minutesUntilDeparture` away, or nil when no valid lead time exists
    /// (mirrors `StopViewModel.canCreateAlarm`'s `> 1` gate).
    static func clamped(_ requested: Int, minutesUntilDeparture: Int) -> Int? {
        guard minutesUntilDeparture > 1 else { return nil }
        let ceiling = min(maximumMinutes, minutesUntilDeparture - 1)
        return min(max(requested, minimumMinutes), ceiling)
    }
}
```

```swift
// OBAKit/Stops/StopPage/Shared/WalkTimeInfo.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The single source of walk time on the Stop page (§4.5): the header chip
/// and the chronological walk line must both read from the same instance.
struct WalkTimeInfo: Equatable {
    /// Rounded up — never promise a shorter walk than reality.
    let walkMinutes: Int
    let distance: CLLocationDistance

    /// Straight-line walk estimate, matching `WalkingDirections.travelTime`.
    /// Returns nil with no user location, an invalid speed, or when the user
    /// is effectively at the stop (<= 40 m, matching `WalkTimeView`).
    static func compute(from userLocation: CLLocation?, to stopLocation: CLLocation?, speedMetersPerSecond: Double) -> WalkTimeInfo? {
        guard let userLocation, let stopLocation, speedMetersPerSecond > 0 else { return nil }
        let distance = userLocation.distance(from: stopLocation)
        guard distance > 40 else { return nil }
        let seconds = distance / speedMetersPerSecond
        return WalkTimeInfo(walkMinutes: Int(ceil(seconds / 60.0)), distance: distance)
    }
}
```

In `OBAKitCore/Models/UserData/UserDataStore.swift`, follow the exact pattern used by `walkingSpeedMetersPerSecond` (same file): add a key `defaultAlarmLeadTimeMinutes` to the keys enum (~line 353) and a property:

```swift
    /// The user's preferred alarm lead time in minutes for one-tap alarms on
    /// the Stop page. Adjustable per-alarm afterward.
    public var defaultAlarmLeadTimeMinutes: Int {
        get {
            let value = userDefaults.integer(forKey: UserDefaultsKeys.defaultAlarmLeadTimeMinutes.rawValue)
            return value == 0 ? 5 : value
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.defaultAlarmLeadTimeMinutes.rawValue)
        }
    }
```

(Adapt the key-enum name/spelling to what that file actually uses — inspect it first; the explorer notes keys are defined around lines 353–373. If a `UserDataStore` protocol declares the store's public surface, add the property there too.)

- [ ] **Step 4: Run tests**

Run: `xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests/AlarmLeadTimeTests -only-testing:OBAKitTests/WalkTimeInfoTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 9 tests pass (or TEST BUILD SUCCEEDED bar).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add alarm lead-time clamp, walk-time computation, and default lead-time setting"
```

---

### Task 5: StopViewModel additions (walk time, alarms, approach fetch)

**Files:**
- Modify: `OBAKit/ViewModels/StopViewModel.swift`
- Test: extend `OBAKitTests` coverage only where pure (the network paths are exercised by build + existing VM test infrastructure; do not fake coverage)

**Interfaces:**
- Produces on `StopViewModel`:
  ```swift
  var walkTime: WalkTimeInfo? { get }                       // computed
  @Published private(set) var alarmsByDepartureID: [String: Alarm]
  func alarm(for arrivalDeparture: ArrivalDeparture) -> Alarm?
  func setAlarm(for: ArrivalDeparture, leadTimeMinutes: Int) async
  func cancelAlarm(for: ArrivalDeparture) async
  func changeAlarm(for: ArrivalDeparture, leadTimeMinutes: Int) async
  func alarmLeadTimeMinutes(_ alarm: Alarm) -> Int          // derive from tripDate - alarmDate
  var defaultAlarmLeadTime: Int { get }
  func approachTripDetails(for: ArrivalDeparture) async -> TripDetails?
  @Published private(set) var alarmError: Error?
  ```
- Consumes: `ObacoAPIService.postAlarm(minutesBefore:arrivalDeparture:userPushID:)` and `deleteAlarm(url:)` (`ObacoAPIService.swift:72,142`), `PushService.pushID()` (`PushService.swift:122`), `ArrivalDepartureDeepLink(arrivalDeparture:regionID:)` (see `AlarmBuilder.swift:112`), `UserDataStore.alarms/.add(alarm:)/.delete(alarm:)`, `apiService.getTrip(tripID:vehicleID:serviceDate:)` (see `TripViewModel.swift:136`), `AlarmLeadTime`, `WalkTimeInfo` (Task 4).

- [ ] **Step 1: Add the code to `StopViewModel.swift`**

Add stored/published state near the other `@Published` vars:

```swift
    /// Alarms owned by this stop's departures, keyed by `ArrivalDeparture.id`.
    /// All four alarm entry points (swipe, pill, row icon, trip panel) read and
    /// write through this single index (§4.7).
    @Published private(set) var alarmsByDepartureID: [String: Alarm] = [:]

    /// Non-nil after an alarm create/cancel fails; consumer shows a toast/alert.
    @Published private(set) var alarmError: Error?

    /// Cache for trip-panel approach timelines, invalidated on each refresh.
    private var approachCache: [String: TripDetails] = [:]
```

Add the members (new `// MARK: - Stop Page` section at the end of the class):

```swift
    // MARK: - Stop Page: Walk Time

    /// Walk time from the user's current location to this stop; the single
    /// source for the header chip and the chronological walk line (§4.5).
    var walkTime: WalkTimeInfo? {
        WalkTimeInfo.compute(
            from: application.locationService.currentLocation,
            to: stop?.location,
            speedMetersPerSecond: application.userDataStore.walkingSpeedMetersPerSecond
        )
    }

    // MARK: - Stop Page: Alarms

    var defaultAlarmLeadTime: Int {
        application.userDataStore.defaultAlarmLeadTimeMinutes
    }

    func alarm(for arrivalDeparture: ArrivalDeparture) -> Alarm? {
        alarmsByDepartureID[arrivalDeparture.id]
    }

    /// Minutes-before-departure for a persisted alarm, derived from its dates.
    func alarmLeadTimeMinutes(_ alarm: Alarm) -> Int {
        guard let tripDate = alarm.tripDate, let alarmDate = alarm.alarmDate else {
            return AlarmLeadTime.defaultMinutes
        }
        return max(AlarmLeadTime.minimumMinutes, Int(round(tripDate.timeIntervalSince(alarmDate) / 60.0)))
    }

    func setAlarm(for arrivalDeparture: ArrivalDeparture, leadTimeMinutes: Int) async {
        guard
            canCreateAlarm(for: arrivalDeparture),
            let obacoService = application.obacoService,
            let pushService = application.pushService,
            let region = application.currentRegion,
            let minutes = AlarmLeadTime.clamped(leadTimeMinutes, minutesUntilDeparture: arrivalDeparture.arrivalDepartureMinutes)
        else { return }

        do {
            let userPushID = await pushService.pushID()
            let alarm = try await obacoService.postAlarm(minutesBefore: minutes, arrivalDeparture: arrivalDeparture, userPushID: userPushID)
            alarm.deepLink = ArrivalDepartureDeepLink(arrivalDeparture: arrivalDeparture, regionID: region.regionIdentifier)
            alarm.set(tripDate: arrivalDeparture.arrivalDepartureDate, alarmOffset: minutes)
            application.userDataStore.add(alarm: alarm)
            alarmsByDepartureID[arrivalDeparture.id] = alarm
            alarmError = nil
        } catch {
            alarmError = error
        }
    }

    func cancelAlarm(for arrivalDeparture: ArrivalDeparture) async {
        guard let alarm = alarm(for: arrivalDeparture) else { return }
        // Optimistic removal; restore on failure.
        alarmsByDepartureID[arrivalDeparture.id] = nil
        do {
            if let obacoService = application.obacoService {
                try await obacoService.deleteAlarm(url: alarm.url)
            }
            application.userDataStore.delete(alarm: alarm)
            alarmError = nil
        } catch {
            alarmsByDepartureID[arrivalDeparture.id] = alarm
            alarmError = error
        }
    }

    /// Obaco has no update endpoint: change = delete + re-post.
    func changeAlarm(for arrivalDeparture: ArrivalDeparture, leadTimeMinutes: Int) async {
        await cancelAlarm(for: arrivalDeparture)
        guard alarmError == nil else { return }
        await setAlarm(for: arrivalDeparture, leadTimeMinutes: leadTimeMinutes)
    }

    /// Rebuilds the departure-id → alarm index by matching each persisted
    /// alarm's deep link against the current departures. Called after each
    /// successful fetch so expired/foreign alarms fall out naturally.
    private func rebuildAlarmIndex() {
        guard let region = application.currentRegion,
              let departures = stopArrivals?.arrivalsAndDepartures
        else {
            alarmsByDepartureID = [:]
            return
        }
        application.userDataStore.deleteExpiredAlarms()
        var index: [String: Alarm] = [:]
        for departure in departures {
            let candidate = ArrivalDepartureDeepLink(arrivalDeparture: departure, regionID: region.regionIdentifier)
            if let match = application.userDataStore.alarms.first(where: { $0.deepLink == candidate }) {
                index[departure.id] = match
            }
        }
        alarmsByDepartureID = index
    }

    // MARK: - Stop Page: Approach Timeline

    /// Trip details backing the trip panel's approach timeline. Fetched on
    /// panel open, cached until the next refresh, live trips only (§4.1).
    func approachTripDetails(for arrivalDeparture: ArrivalDeparture) async -> TripDetails? {
        guard arrivalDeparture.predicted, let apiService = application.apiService else { return nil }
        if let cached = approachCache[arrivalDeparture.tripID] { return cached }
        do {
            let details = try await apiService.getTrip(
                tripID: arrivalDeparture.tripID,
                vehicleID: arrivalDeparture.vehicleID,
                serviceDate: arrivalDeparture.serviceDate
            ).entry
            approachCache[arrivalDeparture.tripID] = details
            return details
        } catch {
            return nil // panel silently omits the timeline on failure
        }
    }
```

Then wire invalidation into `applySuccessfulFetch(stop:arrivals:)` — after `stopArrivals = arrivals`, add:

```swift
        approachCache.removeAll()
        rebuildAlarmIndex()
```

Adjustments to verify while implementing (do not guess):
- `deleteExpiredAlarms()` exists on `UserDataStore` (~line 715) — check its exact name/visibility.
- `ArrivalDepartureDeepLink(arrivalDeparture:regionID:)` — confirm the initializer signature at its definition; `AlarmBuilder.swift:112` shows this exact usage.
- `stop?.location` — `Stop` exposes `location: CLLocation` (used at `StopViewModel.swift:425`).

- [ ] **Step 2: Build**

Run: `xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the existing StopViewModel tests to catch regressions**

Run: `xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20`
Expected: existing suite unaffected (or TEST BUILD SUCCEEDED bar per Global Constraints).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "StopViewModel: walk time, shared alarm index with Obaco set/cancel/change, approach fetch"
```

---

### Task 6: Shared leaf views (glyph, countdown, badge, walk divider)

**Files:**
- Create: `OBAKit/Stops/StopPage/Shared/RealtimeGlyph.swift`
- Create: `OBAKit/Stops/StopPage/Shared/CountdownView.swift`
- Create: `OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift`
- Create: `OBAKit/Stops/StopPage/Shared/WalkLineDivider.swift`

**Interfaces:**
- Produces: `RealtimeGlyph(isRealTime: Bool, color: Color, size: CGFloat)`, `CountdownView(minutes: Int, isRealTime: Bool, color: Color, emphasized: Bool)`, `RouteBadgeView(routeShortName: String, routeColor: Color, size: CGFloat)`, `WalkLineDivider(walkMinutes: Int)`.
- Consumes: `DepartureStatus` (Task 2) for colors at call sites.

- [ ] **Step 1: Implement the four views**

```swift
// OBAKit/Stops/StopPage/Shared/RealtimeGlyph.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The at-a-glance "is this tracked?" signal (§4.1): animated radiating waves
/// for live trips, a static outline clock for schedule-only. Uses an SF Symbol
/// variable-color effect so the system batches animation across the ~15
/// instances a full list shows — never per-instance repeatForever loops.
struct RealtimeGlyph: View {
    let isRealTime: Bool
    let color: Color
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Unary root: one Image; the live/scheduled fork is symbol + modifier state.
        Image(systemName: isRealTime ? "dot.radiowaves.up.forward" : "clock")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isRealTime ? color : Color(uiColor: .secondaryLabel))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isRealTime && !reduceMotion)
            .accessibilityHidden(true) // status is conveyed in the row's combined label
    }
}
```

```swift
// OBAKit/Stops/StopPage/Shared/CountdownView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The "{n}m" countdown with its real-time glyph. Color encodes adherence
/// status, never route (§4.3).
struct CountdownView: View {
    let minutes: Int
    let isRealTime: Bool
    let color: Color
    /// true = card-header size (grouped card / chrono row), false = compact.
    var emphasized: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(minutes)m")
                .font(.system(size: emphasized ? 27 : 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            RealtimeGlyph(isRealTime: isRealTime, color: color, size: emphasized ? 13 : 11)
        }
        .accessibilityElement(children: .ignore)
    }
}
```

```swift
// OBAKit/Stops/StopPage/Shared/RouteBadgeView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge. The ONLY place (besides the grouped
/// card stripe) that renders the route's brand color (§4.3).
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var size: CGFloat = 44

    var body: some View {
        Text(routeShortName)
            .font(.system(size: routeShortName.count <= 2 ? 18 : 13, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(routeColor, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}
```

```swift
// OBAKit/Stops/StopPage/Shared/WalkLineDivider.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The dashed reachability divider in chronological mode: everything above is
/// "just missed", everything below is catchable on foot (§4.5).
struct WalkLineDivider: View {
    let walkMinutes: Int

    private var text: String {
        let fmt = OBALoc("stop_page.walk_divider_fmt", value: "%d MIN WALK — CATCH BELOW", comment: "Divider between departures you'd miss on foot and ones you can still catch. %d is the walk time in minutes.")
        return String(format: fmt, walkMinutes)
    }

    var body: some View {
        HStack(spacing: 10) {
            dash
            Label(text, systemImage: "figure.walk")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            dash
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: OBALoc("stop_page.walk_divider_a11y_fmt", value: "Departures above this point leave sooner than your %d minute walk to the stop", comment: "VoiceOver description of the walk divider. %d is walk minutes."), walkMinutes))
    }

    private var dash: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
            .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
```

- [ ] **Step 2: Regenerate, build**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: BUILD SUCCEEDED. (If `symbolEffect(_:options:isActive:)` has an availability complaint, it's iOS 17+ — fine on our 18.0 floor; fix the exact spelling against the SDK.)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "Add Stop page shared leaf views: realtime glyph, countdown, route badge, walk divider"
```

---

### Task 7: DepartureRowView with swipe actions and context menu

**Files:**
- Create: `OBAKit/Stops/StopPage/Departures/DepartureRowView.swift`

**Interfaces:**
- Produces:
  ```swift
  struct DepartureRowView: View {
      let departure: ArrivalDeparture
      let status: DepartureStatus
      let hasAlarm: Bool
      var style: Style = .normal   // enum Style { case normal, missed, past } (§4.2)
      // Callbacks so the row never touches the VM:
      let onTap: () -> Void
  }
  struct DepartureRowActions {   // reusable swipe/context config, applied at the List call site
      let canAlarm: Bool
      let canSchedule: Bool
      let hasAlarm: Bool
      let onAlarmToggle: () -> Void
      let onSchedule: () -> Void
      let onBookmark: () -> Void
      let onShowTrip: () -> Void
  }
  extension View {
      func departureRowActions(_ actions: DepartureRowActions) -> some View
  }
  ```
- Consumes: `RouteBadgeView`, `CountdownView`, `DepartureStatus` (Tasks 2, 6); `Formatters` for the scheduled-time string; `ArrivalDeparture.routeShortName/.tripHeadsign/.scheduledDate/.arrivalDepartureMinutes/.route.color`.

- [ ] **Step 1: Implement**

```swift
// OBAKit/Stops/StopPage/Departures/DepartureRowView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// One departure row, used by chronological mode and (compact) by grouped
/// expansion. Unary root HStack; all conditional content is interior so the
/// List fast path holds.
struct DepartureRowView: View {
    enum Style {
        case normal
        /// Upcoming but unreachable on foot: dim + strikethrough (§4.2).
        case missed
        /// Already departed: dim only (§4.2).
        case past
    }

    let departure: ArrivalDeparture
    let status: DepartureStatus
    let hasAlarm: Bool
    var style: Style = .normal
    let onTap: () -> Void

    private var dimmed: Bool { style != .normal }

    private var scheduledTimeText: String {
        DateFormatter.localizedString(from: departure.scheduledDate, dateStyle: .none, timeStyle: .short)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            RouteBadgeView(
                routeShortName: departure.routeShortName,
                routeColor: Color(uiColor: departure.route.color ?? ThemeColors.shared.brand)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(departure.tripHeadsign ?? departure.routeShortName)
                    .font(.system(size: 15.5, weight: .bold))
                    .lineLimit(2)
                    .strikethrough(style == .missed)
                HStack(spacing: 6) {
                    Text(scheduledTimeText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(status.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: status.color))
                    if hasAlarm {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
                    }
                }
            }
            Spacer(minLength: 8)
            CountdownView(
                minutes: departure.arrivalDepartureMinutes,
                isRealTime: status.isRealTime,
                color: dimmed ? Color(uiColor: .tertiaryLabel) : Color(uiColor: status.color)
            )
        }
        .opacity(dimmed ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        let fmt = OBALoc("stop_page.row.a11y_fmt", value: "Route %@ to %@, departs in %d minutes, %@", comment: "VoiceOver label for a departure row: route, headsign, minutes, status.")
        return String(format: fmt, departure.routeShortName, departure.tripHeadsign ?? "", departure.arrivalDepartureMinutes, status.accessibilityStatusDescription)
    }
}

/// Swipe + context-menu parity with today's `ArrivalDepartureItem`
/// trailing actions (Alarm / Schedule / Save) and long-press menu.
struct DepartureRowActions {
    let canAlarm: Bool
    let canSchedule: Bool
    let hasAlarm: Bool
    let onAlarmToggle: () -> Void
    let onSchedule: () -> Void
    let onBookmark: () -> Void
    let onShowTrip: () -> Void
}

extension View {
    func departureRowActions(_ actions: DepartureRowActions) -> some View {
        self
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if actions.canAlarm {
                    Button(action: actions.onAlarmToggle) {
                        Label(actions.hasAlarm ? Strings.removeAlarm : Strings.addAlarm, systemImage: actions.hasAlarm ? "bell.slash" : "bell")
                    }
                    .tint(Color(uiColor: ThemeColors.shared.departureOnTime))
                }
                if actions.canSchedule {
                    Button(action: actions.onSchedule) {
                        Label(Strings.schedules, systemImage: "calendar")
                    }
                    .tint(.teal)
                }
                Button(action: actions.onBookmark) {
                    Label(Strings.addBookmark, systemImage: "bookmark")
                }
                .tint(.orange)
            }
            .contextMenu {
                Button(action: actions.onShowTrip) {
                    Label(OBALoc("stop_page.row.show_trip", value: "Show Trip Details", comment: "Context menu action opening the full trip screen"), systemImage: "bus")
                }
                if actions.canAlarm {
                    Button(action: actions.onAlarmToggle) {
                        Label(actions.hasAlarm ? Strings.removeAlarm : Strings.addAlarm, systemImage: "bell")
                    }
                }
                Button(action: actions.onBookmark) {
                    Label(Strings.addBookmark, systemImage: "bookmark")
                }
            }
    }
}
```

Verify `Strings.addAlarm`, `Strings.removeAlarm`, `Strings.schedules`, `Strings.addBookmark` exist in `OBAKitCore/Strings` (`Strings.addAlarm` is used by `AlarmBuilder.swift:143`; `Strings.schedules` by `StopViewController.swift:315`; `Strings.addBookmark` by `StopViewController.swift:362`). If `removeAlarm` is missing, add an `OBALoc` string inline instead.

- [ ] **Step 2: Build**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "Add DepartureRowView with swipe actions and context menu"
```

---

### Task 8: Chronological mode

**Files:**
- Create: `OBAKit/Stops/StopPage/Departures/ChronologicalListView.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift` (render it; still placeholder elsewhere)

**Interfaces:**
- Produces:
  ```swift
  struct ChronologicalListView: View {
      let partition: StopPageListBuilder.ChronologicalPartition<ArrivalDeparture>
      let walkMinutes: Int?
      let showPast: Bool
      let expandedDepartureID: String?
      let statusProvider: (ArrivalDeparture) -> DepartureStatus
      let alarmLookup: (ArrivalDeparture) -> Alarm?
      let actionsProvider: (ArrivalDeparture) -> DepartureRowActions
      let onTogglePast: () -> Void
      let onToggleExpand: (ArrivalDeparture) -> Void
      let panelBuilder: (ArrivalDeparture) -> TripDetailPanelPlaceholder // replaced in Task 10
  }
  struct TripDetailPanelPlaceholder: View // temporary; Task 10 swaps in TripDetailPanelView
  ```
  These are `List` *content* (Sections), not a standalone `List` — `StopPageView` owns the single `List`.
- Consumes: Tasks 2, 3, 6, 7. Past-collapsed persistence key: reuse `"StopViewController.pastDeparturesCollapsed"` (`StopViewController.swift:279` `UserDefaultsKeys`) so the preference round-trips with the old screen.

**Accordion rule (validated):** the open trip panel is a *separate row inserted after* the tapped row inside the same `ForEach` — never height-growth inside a row.

- [ ] **Step 1: Implement**

```swift
// OBAKit/Stops/StopPage/Departures/ChronologicalListView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Temporary stand-in for `TripDetailPanelView` (Task 10). Keeps the accordion
/// mechanics testable in the simulator before the panel exists.
struct TripDetailPanelPlaceholder: View {
    let departure: ArrivalDeparture
    var body: some View {
        Text(departure.routeAndHeadsign)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// Chronological mode: past block, missed block, walk divider, reachable
/// block. Rendered as Sections inside StopPageView's single List (each
/// Section is one rounded card in inset-grouped style).
struct ChronologicalListView: View {
    let partition: StopPageListBuilder.ChronologicalPartition<ArrivalDeparture>
    let walkMinutes: Int?
    let showPast: Bool
    let expandedDepartureID: String?
    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let actionsProvider: (ArrivalDeparture) -> DepartureRowActions
    let onTogglePast: () -> Void
    let onToggleExpand: (ArrivalDeparture) -> Void
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelPlaceholder

    var body: some View {
        // Section header with the Past toggle
        Section {
            if showPast {
                rows(partition.past, style: .past)
            }
        } header: {
            HStack {
                Text(OBALoc("stop_page.section.arrivals_departures", value: "Arrivals & Departures", comment: "Chronological list section header"))
                Spacer()
                if !partition.past.isEmpty {
                    Button(action: onTogglePast) {
                        let fmt = OBALoc("stop_page.past_toggle_fmt", value: "Past · %d", comment: "Button revealing recently departed trips. %d is the count.")
                        Text(showPast ? OBALoc("stop_page.past_toggle_hide", value: "Hide past", comment: "Button hiding recently departed trips") : String(format: fmt, partition.past.count))
                            .font(.caption.weight(.bold))
                    }
                }
            }
        }

        if let walkMinutes, !partition.missed.isEmpty {
            Section {
                rows(partition.missed, style: .missed)
            }
            // Walk divider escapes the card chrome (out-of-card row rules).
            Section {
                WalkLineDivider(walkMinutes: walkMinutes)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        Section {
            rows(partition.reachable, style: .normal)
        }
    }

    @ViewBuilder
    private func rows(_ departures: [ArrivalDeparture], style: DepartureRowView.Style) -> some View {
        // Identity: ArrivalDeparture.id (stable across prediction refreshes).
        ForEach(departures, id: \.id) { departure in
            DepartureRowView(
                departure: departure,
                status: statusProvider(departure),
                hasAlarm: alarmLookup(departure) != nil,
                style: style,
                onTap: { onToggleExpand(departure) }
            )
            .departureRowActions(actionsProvider(departure))

            // Accordion: the panel is an INSERTED SIBLING ROW, keyed off the
            // expanded id — List animates insert/remove smoothly.
            if expandedDepartureID == departure.id {
                panelBuilder(departure)
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `StopPageView`**

Replace `StopPageView.body`'s placeholder Section with real state + content (this version still lacks header/toggle — Task 11 finishes assembly):

```swift
struct StopPageView: View {
    @ObservedObject var viewModel: StopViewModel

    @State private var expandedDepartureID: String?
    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    private var filteredDepartures: [ArrivalDeparture] {
        let all = viewModel.stopArrivals?.arrivalsAndDepartures ?? []
        return viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
    }

    var body: some View {
        List {
            ChronologicalListView(
                partition: StopPageListBuilder.chronologicalPartition(filteredDepartures, walkMinutes: viewModel.walkTime?.walkMinutes),
                walkMinutes: viewModel.walkTime?.walkMinutes,
                showPast: !pastCollapsed,
                expandedDepartureID: expandedDepartureID,
                statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                alarmLookup: { viewModel.alarm(for: $0) },
                actionsProvider: makeActions(for:),
                onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                onToggleExpand: { departure in
                    withAnimation(.snappy) {
                        expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                    }
                },
                panelBuilder: { TripDetailPanelPlaceholder(departure: $0) }
            )
        }
        .listStyle(.insetGrouped)
        .task { await viewModel.start() }
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
    }

    private func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: false,        // wired in Task 12 (region-gated)
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: {
                Task {
                    if viewModel.alarm(for: departure) != nil {
                        await viewModel.cancelAlarm(for: departure)
                    } else {
                        await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime)
                    }
                }
            },
            onSchedule: {},            // Task 12
            onBookmark: {},            // Task 12
            onShowTrip: {}             // Task 12
        )
    }
}
```

- [ ] **Step 3: Build + simulator smoke test**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: BUILD SUCCEEDED. Then boot the app in the iPhone 17 simulator, open any stop from the map, and verify: rows render sorted; tapping a row inserts the placeholder panel row with a smooth animation and tapping again removes it; swiping a row reveals Alarm/Save. **This is the accordion spike from the spec — if the insert/remove animation stutters or clips, stop and fix the row structure before continuing.**

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Add chronological mode with walk partition, past block, and inserted-row accordion"
```

---

### Task 9: Grouped ("By route") mode + segmented toggle

**Files:**
- Create: `OBAKit/Stops/StopPage/Departures/GroupedListView.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift` (toggle + mode switch)

**Interfaces:**
- Produces:
  ```swift
  struct GroupedListView: View {
      let groups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
      let expandedRouteID: RouteID?
      let openTripDepartureID: String?
      let statusProvider: (ArrivalDeparture) -> DepartureStatus
      let alarmLookup: (ArrivalDeparture) -> Alarm?
      let alarmLeadTime: (Alarm) -> Int
      let onToggleRoute: (RouteID) -> Void
      let onToggleTrip: (ArrivalDeparture) -> Void
      let onAlarmToggle: (ArrivalDeparture) -> Void
      let panelBuilder: (ArrivalDeparture) -> TripDetailPanelPlaceholder
  }
  struct StopPageModeToggle: View { let mode: StopSort; let onChange: (StopSort) -> Void }
  ```
- Consumes: Tasks 2, 3, 6, 7; `StopSort` (`.time`/`.route`); `viewModel.updateSortType(_:)`.

- [ ] **Step 1: Implement `GroupedListView`**

```swift
// OBAKit/Stops/StopPage/Departures/GroupedListView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Grouped mode: one Section (= one inset-grouped card) per route, ordered by
/// soonest departure (§4.9). Card header is the next departure; expansion
/// lists every loaded departure; tapping one opens the shared trip panel.
struct GroupedListView: View {
    let groups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
    let expandedRouteID: RouteID?
    let openTripDepartureID: String?
    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let alarmLeadTime: (Alarm) -> Int
    let onToggleRoute: (RouteID) -> Void
    let onToggleTrip: (ArrivalDeparture) -> Void
    let onAlarmToggle: (ArrivalDeparture) -> Void
    let panelBuilder: (ArrivalDeparture) -> TripDetailPanelPlaceholder

    var body: some View {
        ForEach(groups, id: \.routeID) { group in
            Section {
                cardHeader(group)
                if expandedRouteID == group.routeID {
                    expandedRows(group)
                }
            }
        }
    }

    // MARK: - Card header (the route's next departure)

    @ViewBuilder
    private func cardHeader(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        let next = group.next
        let status = statusProvider(next)
        let routeColor = Color(uiColor: next.route.color ?? ThemeColors.shared.brand)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 13) {
                RouteBadgeView(routeShortName: next.routeShortName, routeColor: routeColor, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(next.tripHeadsign ?? next.routeShortName)
                        .font(.system(size: 16.5, weight: .heavy))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(DateFormatter.localizedString(from: next.scheduledDate, dateStyle: .none, timeStyle: .short))
                            .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(status.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(uiColor: status.color))
                    }
                }
                Spacer(minLength: 8)
                CountdownView(minutes: next.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color))
            }

            HStack(spacing: 8) {
                if group.chips.isEmpty {
                    Text(OBALoc("stop_page.grouped.not_loaded", value: "later trips not loaded", comment: "Empty upcoming-chips state; must never imply no later trips exist (§4.4)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(group.chips, id: \.id) { chip in
                        let chipStatus = statusProvider(chip)
                        Text("\(chip.arrivalDepartureMinutes)m")
                            .font(.caption.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(Color(uiColor: chipStatus.color))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(uiColor: chipStatus.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer()
                alarmPill(for: next)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expandedRouteID == group.routeID ? 180 : 0))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(cardStripe(routeColor))
        .contentShape(Rectangle())
        .onTapGesture { onToggleRoute(group.routeID) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groupAccessibilityLabel(group, status: status))
        .accessibilityAddTraits(.isButton)
    }

    /// Route-color accent stripe on the card's left edge — the only other
    /// place route color appears (§4.3).
    private func cardStripe(_ routeColor: Color) -> some View {
        HStack(spacing: 0) {
            routeColor.frame(width: 5)
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }

    private func alarmPill(for departure: ArrivalDeparture) -> some View {
        let alarm = alarmLookup(departure)
        return Button {
            onAlarmToggle(departure)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: alarm != nil ? "bell.fill" : "bell")
                Text(alarm.map { "\(alarmLeadTime($0))m" } ?? Strings.alarm)
                    .monospacedDigit()
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(alarm != nil ? Color.white : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(alarm != nil ? Color(uiColor: ThemeColors.shared.departureOnTime) : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded rows

    @ViewBuilder
    private func expandedRows(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>) -> some View {
        ForEach(group.departures, id: \.id) { departure in
            let status = statusProvider(departure)
            HStack(spacing: 12) {
                Button { onAlarmToggle(departure) } label: {
                    Image(systemName: alarmLookup(departure) != nil ? "bell.fill" : "bell")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(alarmLookup(departure) != nil ? Color.white : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(alarmLookup(departure) != nil ? Color(uiColor: ThemeColors.shared.departureOnTime) : Color.clear, in: Circle())
                        .overlay(Circle().strokeBorder(Color(uiColor: .separator), lineWidth: alarmLookup(departure) != nil ? 0 : 1.5))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(DateFormatter.localizedString(from: departure.scheduledDate, dateStyle: .none, timeStyle: .short))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text("· \(status.label)")
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: status.color))
                    }
                    if status.showsOccupancy, let occupancy = departure.occupancyStatus, occupancy != .unknown {
                        Text(String(describing: occupancy)) // Task 10 replaces with OccupancyStatusView reuse
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                CountdownView(minutes: departure.arrivalDepartureMinutes, isRealTime: status.isRealTime, color: Color(uiColor: status.color), emphasized: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(openTripDepartureID == departure.id ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleTrip(departure) }

            if openTripDepartureID == departure.id {
                panelBuilder(departure)
            }
        }
    }

    private func groupAccessibilityLabel(_ group: StopPageListBuilder.RouteGroup<ArrivalDeparture>, status: DepartureStatus) -> String {
        let fmt = OBALoc("stop_page.grouped.a11y_fmt", value: "Route %@ to %@, next departure in %d minutes, %@. %d more departures loaded.", comment: "VoiceOver label for a grouped route card")
        return String(format: fmt, group.next.routeShortName, group.next.tripHeadsign ?? "", group.next.arrivalDepartureMinutes, status.accessibilityStatusDescription, group.upcoming.count)
    }
}
```

If `Strings.alarm` doesn't exist, use `OBALoc("stop_page.grouped.alarm_pill", value: "Alarm", comment: "Compact alarm pill label when no alarm is set")`.

- [ ] **Step 2: Add the mode toggle and mode switch to `StopPageView`**

Add to `StopPageView` (above the mode content, as an out-of-card Section):

```swift
    @State private var expandedRouteID: RouteID?

    // In body's List, before the mode content:
    Section {
        Picker("", selection: Binding(
            get: { viewModel.stopPreferences.sortType },
            set: { newValue in
                withAnimation {
                    expandedDepartureID = nil
                    expandedRouteID = nil
                    viewModel.updateSortType(newValue)
                }
            }
        )) {
            Text(OBALoc("stop_page.mode.chronological", value: "Chronological", comment: "Stop page mode toggle: flat time-sorted list")).tag(StopSort.time)
            Text(OBALoc("stop_page.mode.by_route", value: "By route", comment: "Stop page mode toggle: grouped by route")).tag(StopSort.route)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // Then switch the mode content:
    if viewModel.stopPreferences.sortType == .time {
        ChronologicalListView(/* as in Task 8 */)
    } else {
        GroupedListView(
            groups: StopPageListBuilder.routeGroups(filteredDepartures),
            expandedRouteID: expandedRouteID,
            openTripDepartureID: expandedDepartureID,
            statusProvider: { DepartureStatus(arrivalDeparture: $0) },
            alarmLookup: { viewModel.alarm(for: $0) },
            alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
            onToggleRoute: { routeID in
                withAnimation(.snappy) {
                    expandedRouteID = expandedRouteID == routeID ? nil : routeID
                    expandedDepartureID = nil
                }
            },
            onToggleTrip: { departure in
                withAnimation(.snappy) {
                    expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                }
            },
            onAlarmToggle: { departure in
                Task {
                    if viewModel.alarm(for: departure) != nil {
                        await viewModel.cancelAlarm(for: departure)
                    } else {
                        await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime)
                    }
                }
            },
            panelBuilder: { TripDetailPanelPlaceholder(departure: $0) }
        )
    }
```

Also seed the last-used-mode default: when the VM's `stopPreferences` come back as the never-customized default, apply a global `"OBALastUsedStopSort"` UserDefaults value — implement as an `.onAppear` one-shot in `StopPageView` that reads `UserDefaults.standard.string(forKey: "OBALastUsedStopSort")`, and write the same key inside the Picker's `set`. Keep it to these two touch points.

- [ ] **Step 3: Build + simulator smoke test**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: BUILD SUCCEEDED. In the simulator: toggle modes (open accordions collapse — §4.6), verify route cards order by soonest departure, chips tint by each departure's own status, single-departure routes read "later trips not loaded".

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Add grouped by-route mode with route cards, status chips, and mode toggle"
```

---

### Task 10: Trip-detail panel (approach timeline + alarm control)

**Files:**
- Create: `OBAKit/Stops/StopPage/TripPanel/ApproachSlice.swift`
- Create: `OBAKit/Stops/StopPage/TripPanel/ApproachTimelineView.swift`
- Create: `OBAKit/Stops/StopPage/TripPanel/AlarmControlView.swift`
- Create: `OBAKit/Stops/StopPage/TripPanel/TripDetailPanelView.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift`, `ChronologicalListView.swift`, `GroupedListView.swift` — replace `TripDetailPanelPlaceholder` with `TripDetailPanelView` (change the `panelBuilder` closure type accordingly), delete the placeholder.
- Test: `OBAKitTests/Stops/StopPage/ApproachSliceTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol ApproachTimelineStop { var stopID: StopID { get }; var stopName: String { get } }
  struct ApproachSlice<S: ApproachTimelineStop> {
      let stops: [S]        // up to 4 upstream + the user's stop (last)
      let vehicleIndex: Int? // index in `stops` of the vehicle's closest stop
      static func make(stopTimes: [S], userStopID: StopID, closestStopID: StopID?) -> ApproachSlice?
      // nil when userStopID absent, or vehicle already past the user's stop
  }
  struct TripDetailPanelView: View {
      let departure: ArrivalDeparture
      let status: DepartureStatus
      let alarm: Alarm?
      let alarmLeadTimeMinutes: Int         // current or default
      let canAlarm: Bool
      let approachLoader: () async -> TripDetails?
      let onSetAlarm: () -> Void
      let onCancelAlarm: () -> Void
      let onChangeAlarm: (Int) -> Void
      let onSchedule: () -> Void
      let onViewFullTrip: () -> Void
  }
  ```
- Consumes: `TripDetails.stopTimes: [TripStopTime]`, `TripStopTime.stopID` (+ resolve stop name via its `stop` reference — check `TripStopTime.swift` for the exact property, `TripStopListItem.swift` shows how the Trip screen reads names), `ArrivalDeparture.tripStatus?.closestStopID` (same field as `TripStopListItem.swift:73`), `AlarmLeadTime` (Task 4), VM methods from Task 5.

- [ ] **Step 1: Write the failing ApproachSlice tests**

```swift
// OBAKitTests/Stops/StopPage/ApproachSliceTests.swift
import XCTest
@testable import OBAKit
import OBAKitCore

private struct StubStop: ApproachTimelineStop {
    let stopID: StopID
    let stopName: String
}

private func stops(_ ids: [String]) -> [StubStop] {
    ids.map { StubStop(stopID: $0, stopName: "Stop \($0)") }
}

final class ApproachSliceTests: XCTestCase {

    func test_takesFourUpstreamStopsPlusUserStop() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "d")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["c", "d", "e", "f", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 1) // "d" within the slice
    }

    func test_shortTrip_usesAllAvailableUpstream() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user"]), userStopID: "user", closestStopID: "a")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["a", "user"])
        XCTAssertEqual(slice?.vehicleIndex, 0)
    }

    func test_vehiclePastUserStop_returnsNil() {
        // Vehicle beyond the user's stop: timeline is meaningless, drop it.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "user", "b"]), userStopID: "user", closestStopID: "b")
        XCTAssertNil(slice)
    }

    func test_vehicleOutsideWindow_hasNilVehicleIndex() {
        // Vehicle is upstream but further back than the 4-stop window.
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "c", "d", "e", "f", "user"]), userStopID: "user", closestStopID: "a")
        XCTAssertEqual(slice?.stops.map(\.stopID), ["c", "d", "e", "f", "user"])
        XCTAssertNil(slice?.vehicleIndex)
    }

    func test_userStopMissing_returnsNil() {
        XCTAssertNil(ApproachSlice.make(stopTimes: stops(["a", "b"]), userStopID: "user", closestStopID: "a"))
    }

    func test_nilClosestStop_stillShowsStops() {
        let slice = ApproachSlice.make(stopTimes: stops(["a", "b", "user"]), userStopID: "user", closestStopID: nil)
        XCTAssertEqual(slice?.stops.map(\.stopID), ["a", "b", "user"])
        XCTAssertNil(slice?.vehicleIndex)
    }
}
```

- [ ] **Step 2: Build to verify failure, then implement `ApproachSlice`**

```swift
// OBAKit/Stops/StopPage/TripPanel/ApproachSlice.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Abstraction over `TripStopTime` so the windowing logic is testable with
/// stubs (the real type only decodes from JSON).
protocol ApproachTimelineStop {
    var stopID: StopID { get }
    var stopName: String { get }
}

/// The trip panel's approach window: the user's stop plus up to 4 upstream
/// stops, with the vehicle's position resolved from `closestStopID` — the
/// same field the Trip screen uses (`TripStopListItem`).
struct ApproachSlice<S: ApproachTimelineStop> {
    let stops: [S]
    let vehicleIndex: Int?

    static func make(stopTimes: [S], userStopID: StopID, closestStopID: StopID?) -> ApproachSlice? {
        guard let userIndex = stopTimes.firstIndex(where: { $0.stopID == userStopID }) else { return nil }

        if let closestStopID,
           let vehicleAbsolute = stopTimes.firstIndex(where: { $0.stopID == closestStopID }),
           vehicleAbsolute > userIndex {
            return nil // vehicle already past the user's stop
        }

        let start = max(0, userIndex - 4)
        let window = Array(stopTimes[start...userIndex])
        let vehicleIndex = closestStopID.flatMap { closest in
            window.firstIndex(where: { $0.stopID == closest })
        }
        return ApproachSlice(stops: window, vehicleIndex: vehicleIndex)
    }
}
```

Conform the real model where the panel builds the slice (in `TripDetailPanelView`, below): check `TripStopTime` for its stop-name access (the Trip screen resolves names via the stop reference; mirror what `TripStopListItem.swift` does) and add:

```swift
extension TripStopTime: ApproachTimelineStop {
    // stopID exists on the model already; expose stopName from the resolved stop reference.
    var stopName: String { stop.name } // adjust to the actual property found in TripStopTime.swift
}
```

- [ ] **Step 3: Run the slice tests**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests/ApproachSliceTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: 6 tests pass (or TEST BUILD SUCCEEDED bar).

- [ ] **Step 4: Implement the panel views**

```swift
// OBAKit/Stops/StopPage/TripPanel/AlarmControlView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The trip panel's alarm block: a single "Set an alarm" button by default;
/// once set, an info row with Change (inline stepper) and Cancel.
struct AlarmControlView: View {
    let alarmIsSet: Bool
    let leadTimeMinutes: Int
    let maxLeadTime: Int   // min(15, minutesUntilDeparture - 1)
    let onSet: () -> Void
    let onCancel: () -> Void
    let onChange: (Int) -> Void

    @State private var editing = false
    @State private var pendingMinutes: Int = AlarmLeadTime.defaultMinutes

    var body: some View {
        VStack(spacing: 0) {
            if !alarmIsSet {
                Button(action: onSet) {
                    Label(OBALoc("stop_page.alarm.set", value: "Set an alarm", comment: "Primary alarm button in the trip panel"), systemImage: "bell")
                        .font(.system(size: 15, weight: .heavy))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: ThemeColors.shared.departureOnTime))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(Color(uiColor: ThemeColors.shared.departureOnTime))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: ThemeColors.shared.departureOnTime).opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(OBALoc("stop_page.alarm.set_title", value: "Alarm set", comment: "Title of the set-alarm info row"))
                            .font(.subheadline.weight(.bold))
                        Text(String(format: OBALoc("stop_page.alarm.buzz_fmt", value: "Buzz %d min before it arrives", comment: "Subtitle of the set-alarm info row. %d is lead-time minutes."), leadTimeMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !editing {
                        Button(OBALoc("stop_page.alarm.change", value: "Change", comment: "Reveals the alarm lead-time stepper")) {
                            pendingMinutes = leadTimeMinutes
                            editing = true
                        }
                        .buttonStyle(.bordered)
                        Button(Strings.cancel, role: .destructive, action: onCancel)
                            .buttonStyle(.bordered)
                    }
                }
                if editing {
                    HStack {
                        Text(OBALoc("stop_page.alarm.minutes_before", value: "Minutes before", comment: "Stepper label"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $pendingMinutes, in: AlarmLeadTime.minimumMinutes...max(AlarmLeadTime.minimumMinutes, maxLeadTime)) {
                            Text("\(pendingMinutes)m").font(.subheadline.weight(.heavy)).monospacedDigit()
                        }
                        .fixedSize()
                        Button(OBALoc("stop_page.alarm.done", value: "Done", comment: "Commits the lead-time change")) {
                            editing = false
                            onChange(pendingMinutes)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(uiColor: ThemeColors.shared.departureOnTime))
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}
```

```swift
// OBAKit/Stops/StopPage/TripPanel/ApproachTimelineView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Vertical line-and-dot approach timeline: upstream stops leading to the
/// user's stop with a "bus here" marker at the vehicle's position. Live
/// trips only (§4.1). Stops at/behind the bus are gray, stops between bus
/// and user use the route color.
struct ApproachTimelineView: View {
    struct Row: Identifiable {
        let id: String       // stopID
        let name: String
        let isUserStop: Bool
        let isVehicleHere: Bool
        let isPassed: Bool   // at or behind the vehicle
    }

    let rows: [Row]
    let minutesAway: Int
    let routeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(row.isPassed ? Color(uiColor: .quaternaryLabel) : routeColor, lineWidth: 2.5)
                        .background(Circle().fill(row.isUserStop ? routeColor : Color.clear))
                        .frame(width: row.isUserStop ? 12 : 9, height: row.isUserStop ? 12 : 9)
                    Text(row.name)
                        .font(.system(size: 13.5, weight: row.isUserStop ? .heavy : .medium))
                        .foregroundStyle(row.isUserStop ? .primary : (row.isPassed ? Color(uiColor: .tertiaryLabel) : .secondary))
                        .lineLimit(1)
                    if row.isUserStop {
                        Text(OBALoc("stop_page.timeline.your_stop", value: "· your stop", comment: "Marker on the user's stop in the approach timeline"))
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.isVehicleHere {
                        Label(String(format: OBALoc("stop_page.timeline.bus_here_fmt", value: "bus here · %dm away", comment: "Vehicle-position pill. %d is minutes to the user's stop."), minutesAway), systemImage: "bus")
                            .font(.caption2.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(routeColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(routeColor.opacity(0.14), in: Capsule())
                    }
                }
                .frame(minHeight: 30)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
```

```swift
// OBAKit/Stops/StopPage/TripPanel/TripDetailPanelView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The shared "second tap" panel (§4.6), rendered as an inserted row beneath
/// its departure in either mode: live-vehicle strip (or the scheduled-only
/// honesty notice), approach timeline, alarm control, and actions.
struct TripDetailPanelView: View {
    let departure: ArrivalDeparture
    let status: DepartureStatus
    let alarm: Alarm?
    let alarmLeadTimeMinutes: Int
    let canAlarm: Bool
    let approachLoader: () async -> TripDetails?
    let onSetAlarm: () -> Void
    let onCancelAlarm: () -> Void
    let onChangeAlarm: (Int) -> Void
    let onSchedule: () -> Void
    let onViewFullTrip: () -> Void

    @State private var tripDetails: TripDetails?
    @State private var timelineLoading = false

    private var routeColor: Color {
        Color(uiColor: departure.route.color ?? ThemeColors.shared.brand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Live vehicle strip / scheduled-only notice (§4.1)
            HStack(spacing: 8) {
                RealtimeGlyph(isRealTime: status.isRealTime, color: routeColor, size: 15)
                if status.isRealTime {
                    Text(String(format: OBALoc("stop_page.panel.live_vehicle_fmt", value: "Live · vehicle %@", comment: "Trip panel live strip. %@ is the vehicle id."), departure.vehicleID ?? "—"))
                        .font(.footnote.weight(.bold))
                } else {
                    Text(OBALoc("stop_page.panel.scheduled_strip", value: "Scheduled · no live position yet", comment: "Trip panel strip for schedule-only trips"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            if status.isRealTime {
                if let slice = approachSlice {
                    ApproachTimelineView(
                        rows: timelineRows(slice),
                        minutesAway: departure.arrivalDepartureMinutes,
                        routeColor: routeColor
                    )
                } else if timelineLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                // fetch failed / vehicle past window: omit silently
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(OBALoc("stop_page.panel.scheduled_title", value: "Scheduled time only", comment: "Title of the schedule-only notice"))
                            .font(.footnote.weight(.bold))
                        Text(OBALoc("stop_page.panel.scheduled_body", value: "No live signal from this bus yet — this is when it's supposed to arrive. It may run early, late, or not at all.", comment: "Body of the schedule-only notice; must communicate uncertainty (§4.1/§4.4)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }
            }

            if canAlarm {
                AlarmControlView(
                    alarmIsSet: alarm != nil,
                    leadTimeMinutes: alarmLeadTimeMinutes,
                    maxLeadTime: min(AlarmLeadTime.maximumMinutes, departure.arrivalDepartureMinutes - 1),
                    onSet: onSetAlarm,
                    onCancel: onCancelAlarm,
                    onChange: onChangeAlarm
                )
            }

            HStack(spacing: 10) {
                Button(action: onSchedule) {
                    Label(Strings.schedules, systemImage: "calendar")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                Button(action: onViewFullTrip) {
                    Label(OBALoc("stop_page.panel.full_trip", value: "View full trip", comment: "Opens the full trip screen"), systemImage: "bus")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .task(id: departure.id) {
            guard status.isRealTime, tripDetails == nil else { return }
            timelineLoading = true
            tripDetails = await approachLoader()
            timelineLoading = false
        }
    }

    private var approachSlice: ApproachSlice<TripStopTime>? {
        guard let stopTimes = tripDetails?.stopTimes else { return nil }
        return ApproachSlice.make(
            stopTimes: stopTimes,
            userStopID: departure.stopID,
            closestStopID: departure.tripStatus?.closestStopID
        )
    }

    private func timelineRows(_ slice: ApproachSlice<TripStopTime>) -> [ApproachTimelineView.Row] {
        slice.stops.enumerated().map { index, stopTime in
            ApproachTimelineView.Row(
                id: stopTime.stopID,
                name: stopTime.stopName,
                isUserStop: index == slice.stops.count - 1,
                isVehicleHere: slice.vehicleIndex == index,
                isPassed: slice.vehicleIndex.map { index <= $0 } ?? false
            )
        }
    }
}
```

- [ ] **Step 5: Replace the placeholder**

In `ChronologicalListView` and `GroupedListView`, change `panelBuilder`'s type from `(ArrivalDeparture) -> TripDetailPanelPlaceholder` to `(ArrivalDeparture) -> TripDetailPanelView`; delete `TripDetailPanelPlaceholder`. In `StopPageView`, build the real panel:

```swift
    private func makePanel(for departure: ArrivalDeparture) -> TripDetailPanelView {
        let status = DepartureStatus(arrivalDeparture: departure)
        let alarm = viewModel.alarm(for: departure)
        return TripDetailPanelView(
            departure: departure,
            status: status,
            alarm: alarm,
            alarmLeadTimeMinutes: alarm.map { viewModel.alarmLeadTimeMinutes($0) } ?? viewModel.defaultAlarmLeadTime,
            canAlarm: viewModel.canCreateAlarm(for: departure),
            approachLoader: { await viewModel.approachTripDetails(for: departure) },
            onSetAlarm: { Task { await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime) } },
            onCancelAlarm: { Task { await viewModel.cancelAlarm(for: departure) } },
            onChangeAlarm: { minutes in Task { await viewModel.changeAlarm(for: departure, leadTimeMinutes: minutes) } },
            onSchedule: {},      // Task 12
            onViewFullTrip: {}   // Task 12
        )
    }
```

Pass `panelBuilder: makePanel(for:)` at both call sites.

- [ ] **Step 6: Build + simulator smoke test, then commit**

Run the standard build; in the simulator verify: expanding a live departure shows the strip and (after the fetch) the timeline with the bus pill; a schedule-only departure shows the honesty notice with a clock glyph and no occupancy; setting an alarm from the panel flips the swipe action, pill, and row icon simultaneously (§4.7).

```bash
git add -A && git commit -m "Add trip-detail panel with approach timeline and alarm control"
```

---

### Task 11: Header card, live status row, footer, alerts/surveys/donations

**Files:**
- Create: `OBAKit/Stops/StopPage/StopPageHeaderView.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift` (final assembly)

**Interfaces:**
- Produces: `StopPageHeaderView(stop: Stop, walkTime: WalkTimeInfo?, snapshotLoader: (CGSize) async -> UIImage?)`.
- Consumes: `MapSnapshotter` (`OBAKit/Mapping/MapSnapshotter.swift` — callback-based; bridge with a continuation; see how `StopHeaderView` in `StopHeaderController.swift` configures it, including `ThemeColors.shared.mapSnapshotOverlayColor`), `Formatters` for the `Stop #### · direction` subhead (`StopHeaderView` shows the existing format strings to reuse), `viewModel.statusText`, `viewModel.currentSurvey`, `viewModel.stopArrivals?.serviceAlerts`, `viewModel.loadMoreDepartures()`, `viewModel.isLoadMoreExhausted`.

- [ ] **Step 1: Implement `StopPageHeaderView`**

```swift
// OBAKit/Stops/StopPage/StopPageHeaderView.swift
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The inset map-card header: snapshot background, stop identity, and the
/// walk chip — the single visual source of walk time (§4.5). Tap toggles the
/// routes-served line (parity with the old header).
struct StopPageHeaderView: View {
    let stop: Stop
    let walkTime: WalkTimeInfo?
    let snapshotLoader: (CGSize) async -> UIImage?

    @State private var snapshot: UIImage?
    @State private var showsRoutes = false

    private var subtitle: String {
        // Reuse the exact format the old header shows; see StopHeaderView for
        // the localized "Stop #%@" + direction strings and mirror them.
        Formatters.formattedCodeAndDirection(stop: stop)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground)
                }
            }
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0.92), Color(uiColor: .systemBackground).opacity(0.4), .clear],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(.system(size: 22, weight: .heavy))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                if showsRoutes {
                    Text(stop.routes.map(\.shortName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let walkTime {
                Label(walkChipText(walkTime), systemImage: "figure.walk")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(uiColor: ThemeColors.shared.departureOnTime), in: Capsule())
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { showsRoutes.toggle() } }
        .task {
            // MapSnapshotter needs concrete dimensions; commit to the card size.
            snapshot = await snapshotLoader(CGSize(width: UIScreen.main.bounds.width - 40, height: 150))
        }
        .accessibilityElement(children: .combine)
    }

    private func walkChipText(_ info: WalkTimeInfo) -> String {
        let distance = Formatters.formattedDistance(info.distance)
        let fmt = OBALoc("stop_page.walk_chip_fmt", value: "%d min walk · %@", comment: "Walk chip on the header card. %d minutes, %@ formatted distance.")
        return String(format: fmt, info.walkMinutes, distance)
    }
}
```

Verification notes for the implementer: `Formatters.formattedCodeAndDirection` and `Formatters.formattedDistance` — check `Formatters.swift` and `StopHeaderController.swift`/`WalkTimeView.swift` for the actual helper names; if they differ, use the existing ones rather than inventing new formatting. Bridge `MapSnapshotter` in `StopPageViewController` (it owns `application`):

```swift
    func loadSnapshot(size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            // Mirror StopHeaderView's MapSnapshotter configuration (stop annotation,
            // overlay color, zoom) — see StopHeaderController.swift.
            let snapshotter = MapSnapshotter(size: size, stopIconFactory: application.stopIconFactory)
            snapshotter.snapshot(stop: viewModel.stop!, traitCollection: traitCollection) { image in
                continuation.resume(returning: image)
            }
        }
    }
```

(Adjust to `MapSnapshotter`'s real initializer/method — read the file first; do not guess.) Pass it into `StopPageView` as a closure so the view stays UIKit-free.

- [ ] **Step 2: Final `StopPageView` assembly**

Assemble the full list order (spec "Screen structure"): header card (out-of-card Section, `listRowInsets(EdgeInsets())` + clear background) → live status row (`viewModel.statusText` with a pulsing dot: `Circle` 7pt in `departureOnTime`, `.symbolEffect`-free — use `.opacity` phase animation gated on Reduce Motion, or static when reduced) → survey card if `viewModel.currentSurvey != nil` (reuse the same SwiftUI/hosted view the old screen's survey section uses — find it via `surveySection` in `StopViewController.swift` and render its content view here; if it is UIKit-only, wrap in a representable) → service alerts Section (rows: `Image(systemName: "exclamationmark.triangle.fill")` + alert title from `viewModel.stopArrivals?.serviceAlerts`, tap → callback to the hosting VC which pushes the existing alert detail via `application.viewRouter`) → mode toggle → mode content → footer Section:

```swift
    Section {
        if !viewModel.isLoadMoreExhausted {
            Button {
                Task { await viewModel.loadMoreDepartures() }
            } label: {
                Label(OBALoc("stop_page.load_more", value: "Load more", comment: "Extends the departure time window"), systemImage: "plus")
                    .font(.system(size: 14.5, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        Text(String(format: OBALoc("stop_page.attribution_fmt", value: "Real-time data provided by %@", comment: "Data attribution footer. %@ is the region/agency name."), viewModel.stop?.routes.first?.agency.name ?? ""))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
    }
```

Also add the empty states: when `filteredDepartures.isEmpty && !viewModel.isLoading` show "No departures in the next \(viewModel.minutesAfter) minutes" (never "no more buses" — §4.4); when everything is filtered out (`!all.isEmpty && filtered.isEmpty`) show "All routes at this stop are filtered" with a button invoking the filter callback; when `viewModel.operationError != nil` and there's no data, show the error text with a Retry button calling `viewModel.refresh()`.

Check the attribution source: the old screen has a `dataAttributionSection` (`StopViewController.swift`, search `dataAttribution`) — reuse its string/source instead of the agency guess above if it differs.

Donations: check `donationsSection` in `StopViewController.swift`; if it renders a SwiftUI view (donations UI is SwiftUI elsewhere), embed the same view behind `if` on the same condition; if it's UIKit-only and heavy, defer to the parity task (Task 12) with a note — do not silently drop it.

- [ ] **Step 3: Build + simulator smoke test, then commit**

```bash
git add -A && git commit -m "Assemble Stop page: header card, status row, alerts, surveys, footer, empty states"
```

---

### Task 12: Hosting-VC chrome parity (menus, filter, navigation, Previewable)

**Files:**
- Modify: `OBAKit/Stops/StopPage/StopPageViewController.swift`
- Modify: `OBAKit/Stops/StopPage/StopPageView.swift` (navigation callbacks struct)

**Interfaces:**
- Produces: `StopPageNavigationHandler` — a struct of closures injected into `StopPageView` for everything that leaves the screen: `showTrip(ArrivalDeparture)`, `showSchedule()`, `showAlertDetail(ServiceAlert)`, `showBookmarkEditor(ArrivalDeparture?)`, `showFilter()`. The hosting VC implements them with the same code paths `StopViewController` uses.
- Consumes: `StopViewController.swift` as the reference implementation — port these, adapting `self`/`viewModel` references (menu code is at the cited lines; it is UIKit and lives on the hosting VC):
  - `filterMenu()` (`:327-359`) and Filter bar button (`configureTabBarButtons()` `:300-321`)
  - `fileMenu()` (`:361-377`), `locationMenu()` (`:379-420`), `helpMenu()` (`:446-452`) — compose the More pulldown WITHOUT `sortMenu()` (the toggle supersedes it)
  - Schedules bar button → `showScheduleForStop` (find its implementation in `StopViewController` and port)
  - Route filter presentation `filter()` (`:1216` — presents SwiftUI `StopPreferencesWrappedView` in a `UIHostingController`)
  - `Previewable` conformance (see `StopViewController`'s implementation, search `Previewable`)

- [ ] **Step 1: Port nav-bar items and menus onto `StopPageViewController`**

In `viewDidLoad`, mirror `configureTabBarButtons()`: right bar items = More menu (File/Location/Help submenus, no Sort), Filter menu, Schedules button. Rebuild the menus when `viewModel.stopPreferences` or `viewModel.stopArrivals` changes — subscribe with Combine exactly as `StopViewController.bindViewModel()` does (`StopViewController.swift:198` and the binding extension at `:1267` show the pattern):

```swift
    private var cancellables = Set<AnyCancellable>()

    private func bindChrome() {
        viewModel.$stop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stop in
                guard let self, let stop else { return }
                self.title = Formatters.formattedTitle(stop: stop)
                self.configureBarButtons()
            }
            .store(in: &cancellables)

        viewModel.$stopPreferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.configureBarButtons() }
            .store(in: &cancellables)
    }
```

`configureBarButtons()` is the ported `configureTabBarButtons()` minus the sort menu. Port the menu bodies verbatim from the cited lines, changing `self.stop` → `viewModel.stop`, `self.stopArrivals` → `viewModel.stopArrivals`.

- [ ] **Step 2: Wire `StopPageNavigationHandler`**

```swift
/// Everything that navigates away from the Stop page, implemented by the
/// hosting VC so SwiftUI stays router-free.
struct StopPageNavigationHandler {
    let showTrip: (ArrivalDeparture) -> Void
    let showSchedule: () -> Void
    let showAlertDetail: (ServiceAlert) -> Void
    let showBookmarkEditor: (ArrivalDeparture?) -> Void
    let showFilter: () -> Void
}
```

In `StopPageViewController`, construct it with:
- `showTrip`: `application.viewRouter.navigateTo(arrivalDeparture: $0, from: self)`
- `showSchedule`: port `showScheduleForStop` from `StopViewController`
- `showAlertDetail`: the same presentation the old screen uses for a tapped alert (search `StopViewController` for its service-alert selection handling and port)
- `showBookmarkEditor`: port the `addBookmark(sender:)` / arrival-bookmark flow (`StopViewController` — search `BookmarkEditor`); pass `nil` for the stop-level bookmark, an `ArrivalDeparture` for trip bookmarks
- `showFilter`: port `filter()` (`:1216`)

Rebuild `rootView` with the handler included (add `let navigation: StopPageNavigationHandler` to `StopPageView` and thread it to `makeActions`/`makePanel`: `onShowTrip` → `navigation.showTrip(departure)`, `onSchedule` → `navigation.showSchedule()`, `onBookmark` → `navigation.showBookmarkEditor(departure)`; alert row taps → `navigation.showAlertDetail(alert)`). Set `canSchedule` from the same region gating the old screen uses (find the region-gated Schedule condition in `StopArrivalItem.swift:54`'s action construction and reuse it).

Add the `Previewable` conformance ported from `StopViewController` (search `extension StopViewController: Previewable`), so map peeks work.

Add the context-menu trip preview: in `departureRowActions`, extend `.contextMenu` to `.contextMenu(menuItems:preview:)` where the preview is:

```swift
    TripViewControllerPreview(departure: departure, application: application)
        .frame(width: 320, height: 400)
```

with:

```swift
/// Lazily-built UIKit preview for row long-presses; constructed only when the
/// preview is actually presented.
struct TripViewControllerPreview: UIViewControllerRepresentable {
    let departure: ArrivalDeparture
    let application: Application
    func makeUIViewController(context: Context) -> TripViewController {
        TripViewController(application: application, arrivalDeparture: departure)
    }
    func updateUIViewController(_ uiViewController: TripViewController, context: Context) {}
}
```

(This requires `application` to reach the row call site — pass it through `StopPageNavigationHandler` as `let makeTripPreview: (ArrivalDeparture) -> AnyView` built by the hosting VC instead, keeping `Application` out of the view layer. AnyView is acceptable here: it's inside a lazily-evaluated preview closure, not row structure.)

- [ ] **Step 3: Build + full simulator parity pass, then commit**

Verify in the simulator: More menu (bookmark/alerts/nearby/walking directions/report), Filter menu + sheet, Schedules button, long-press preview opens, swipe Save opens the bookmark editor, panel's "View full trip" pushes the trip screen.

```bash
git add -A && git commit -m "Stop page chrome parity: menus, filter, navigation handler, trip previews"
```

---

### Task 13: Settings row for default alarm lead time

**Files:**
- Modify: `OBAKit/Settings/SettingsViewController.swift` (Alerts section — search `alertsSection` or the section registered around the "Alerts" title)

- [ ] **Step 1: Add the row**

Follow the walking-speed preset row pattern in the same file (segmented `SegmentedRow` or `ActionSheetRow` — match what the file uses; the walking-speed section shows the house style). Options: 2, 5, 10 minutes; read/write `application.userDataStore.defaultAlarmLeadTimeMinutes`:

```swift
    section <<< ActionSheetRow<Int> {
        $0.tag = "defaultAlarmLeadTimeMinutes"
        $0.title = OBALoc("settings_controller.alerts_section.default_alarm_lead_time", value: "Default alarm lead time", comment: "Settings > Alerts > default minutes-before for one-tap departure alarms")
        $0.options = [2, 5, 10]
        $0.value = application.userDataStore.defaultAlarmLeadTimeMinutes
        $0.displayValueFor = { value in
            guard let value else { return nil }
            return String(format: OBALoc("settings_controller.alerts_section.lead_time_fmt", value: "%d minutes", comment: "Lead-time option label"), value)
        }
    }.onChange { [weak self] row in
        guard let self, let value = row.value else { return }
        self.application.userDataStore.defaultAlarmLeadTimeMinutes = value
    }
```

(Adapt to the file's actual save pattern — it may batch values in `form.values()` on exit like the experimental toggles; if so, register/save the same way instead of `.onChange`.)

- [ ] **Step 2: Build, verify in Settings UI, commit**

```bash
git add -A && git commit -m "Settings: default alarm lead time (2/5/10 min)"
```

---

### Task 14: Full verification pass + doc touch-ups

**Files:**
- Modify: `CLAUDE.md` (stale "Target iOS Version: 17.0+" → "18.0+")

- [ ] **Step 1: Run the full unit-test suite**

Run: `scripts/generate_project OneBusAway && xcodebuild build-for-testing -scheme 'App' -project 'OBAKit.xcodeproj' -destination 'platform=iOS Simulator,name=iPhone 17' -quiet && xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -15`
Expected: suite green (or TEST BUILD SUCCEEDED bar with the known runner crash, reported honestly).

- [ ] **Step 2: SwiftLint**

Run: `scripts/swiftlint.sh`
Expected: no new violations in `OBAKit/Stops/StopPage/` or modified files.

- [ ] **Step 3: Manual simulator walkthrough (both modes, against the live Puget Sound region)**

Checklist — each item maps to a spec requirement:
- [ ] Chronological: sorted rows; walk chip and walk divider show the same minutes (§4.5); missed rows dim+strikethrough, past rows dim only (§4.2)
- [ ] Past toggle reveals/hides the dimmed past card; state persists across screens (shared key with old UI)
- [ ] Grouped: cards ordered by soonest (§4.9); chips tinted per-departure; "later trips not loaded" on single-trip routes (§4.4)
- [ ] Mode toggle collapses open accordions (§4.6) and round-trips with the old screen's Sort menu (flip the flag off, check the old screen shows the same sort)
- [ ] Schedule-only departure: clock glyph, gray countdown, "schedule data", no occupancy anywhere, honesty notice in panel (§4.1)
- [ ] Alarm set/cancel/change from all four surfaces stays in sync (§4.7); alarm survives app relaunch (persisted in UserDataStore) and appears in Recents' alarm list
- [ ] Load more extends the window; button hides when exhausted
- [ ] Reduce Motion (Settings → Accessibility → Motion in the simulator): glyphs and status dot static
- [ ] Dark mode: status colors legible, header scrim correct
- [ ] VoiceOver: rows read as single elements with route/headsign/minutes/status; swipe actions reachable via the rotor
- [ ] Flag OFF (Settings → Experimental): old StopViewController returns, all existing behavior intact

- [ ] **Step 4: Fix CLAUDE.md target and commit**

In `CLAUDE.md`, change `- **Target iOS Version**: 17.0+` to `- **Target iOS Version**: 18.0+`.

```bash
git add -A && git commit -m "Stop page rethink: verification pass; fix stale iOS target in CLAUDE.md"
```

---

## Self-Review Notes (already applied)

- **Spec coverage**: flag/router (T1), status gate §4.1 (T2), partition/grouping §4.2/§4.5/§4.9 (T3), clamp + walk source + lead-time setting (T4, T13), VM alarm/walk/approach (T5), glyph §4.8 + shared views (T6), rows + swipe/context (T7), chrono mode + accordion spike (T8), grouped mode + toggle + last-used-mode seed (T9), trip panel §4.6 + timeline + alarm UX (T10), header/status/alerts/surveys/footer/empty states §4.4 (T11), menus/filter/navigation/Previewable/previews (T12), settings row (T13), verification + a11y + dark mode + flag-off regression (T14).
- **Known intentional deferrals**: `@Observable` migration (post-legacy-retirement), donations card may land in T12 if UIKit-only (flagged in T11, never silently dropped).
- **Type consistency**: `DepartureStatus`, `StopPageListBuilder.ChronologicalPartition/RouteGroup`, `DepartureRowActions`, `TripDetailPanelView`, `StopPageNavigationHandler`, `WalkTimeInfo`, `AlarmLeadTime`, `ApproachSlice` are each defined once and consumed by name in later tasks.
- **Codebase-verification hooks**: wherever the plan touches API surfaces it couldn't fully verify (`MapSnapshotter` init, `TripStopTime` stop-name property, `UserDataStore` key-enum spelling, `Strings.*` constants, Eureka save pattern), the step says "read the file first, adapt, don't guess" with the exact file to read.
