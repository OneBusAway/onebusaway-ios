# Onboarding Rethink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded per-app onboarding navigation controller with a shared, versioned step registry in OBAKit so first-run users get the redesigned five-screen flow and existing users are shown any never-seen step (initially: push notifications) exactly once at launch.

**Architecture:** A pure model layer (`OnboardingStep` registry + `OnboardingStepStore` seen-version persistence + `OnboardingEnvironment` snapshot) computes the flow as `eligible ∧ unseen, sorted by weight`. A SwiftUI `OnboardingFlowView` renders the computed steps inside a shared scaffold; an `@objc` `OnboardingFlowController` (plain `UIViewController` embedding a hosting controller — `UIHostingController` subclasses can't be ObjC-exposed) replaces `OnboardingNavigationController` at the AppDelegate call sites. Spec: `docs/superpowers/specs/2026-07-17-onboarding-rethink-design.md`.

**Tech Stack:** Swift, SwiftUI, UIKit hosting, UserNotifications, CoreLocation, XCTest (+Nimble available), XcodeGen.

## Global Constraints

- iOS 18.0+ target; Swift 6 concurrency ratchet is **enforcing** — new files must produce zero concurrency warnings. Model types are `Sendable`; UI types are `@MainActor`.
- OBAKitCore must stay application-extension-safe; everything here lives in **OBAKit** (UI framework) or app targets, so `UIApplication.shared` is allowed.
- UserDefaults key for seen versions: exactly `OBAOnboardingSeenStepVersions`. Backfill set: exactly `{welcome, location, region, done}` (never `notifications`).
- Step weights: migration 5, welcome 10, location 20, region 30, notifications 40, done 99. All versions start at 1.
- User-facing strings use `OBALoc("onboarding.<screen>.<name>", value:comment:)`. Accent color comes from the app theme (`Color.accentColor` / `.tint`), never a hardcoded lime.
- `TEST_ONBOARDING=1` env var (DEBUG only) forces the full flow, ignoring store and eligibility.
- After adding/removing files: `scripts/generate_project OneBusAway` before building (XcodeGen). Simulator destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Two deliberate deviations from the spec's pseudocode, both approved in spec decisions or noted here:
  1. `makeView` is not stored in the step struct; `OnboardingFlowView` switches on `step.id`. Keeps the model layer SwiftUI-free and testable. Adding a step = one registry entry + one switch case.
  2. The notifications screen calls `UNUserNotificationCenter.requestAuthorization` + `registerForRemoteNotifications()` directly instead of awaiting `PushService.pushID()`, because `OBACloudPushService.requestPushID`'s callback never fires when the user denies (the flow would hang). Token delivery still flows through the existing AppDelegate → `pushService` wiring, so this is the same OS-level path the spec requires.

---

### Task 1: OnboardingStepStore (seen versions + backfill)

**Files:**
- Create: `OBAKit/Onboarding/Flow/OnboardingStepStore.swift`
- Create: `OBAKitTests/Onboarding/OnboardingStepStoreTests.swift`

**Interfaces:**
- Consumes: nothing (foundation task). `OnboardingStepID` is defined here (the store is its first consumer; Task 2's registry reuses it).
- Produces:
  - `public enum OnboardingStepID: String, CaseIterable, Sendable { case migration, welcome, location, region, notifications, done }`
  - `@MainActor public final class OnboardingStepStore` with `init(userDefaults: UserDefaults)`, `func seenVersion(of: OnboardingStepID) -> Int`, `func markSeen(_: OnboardingStepID, version: Int)`, `var isEmpty: Bool`, `@discardableResult func backfillIfNeeded(hasCurrentRegion: Bool) -> Bool`, `static let userDefaultsKey = "OBAOnboardingSeenStepVersions"`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  OnboardingStepStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit

@MainActor
final class OnboardingStepStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: OnboardingStepStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "OnboardingStepStoreTests-\(UUID().uuidString)")
        store = OnboardingStepStore(userDefaults: userDefaults)
    }

    func test_unseenStep_hasVersionZero() {
        XCTAssertEqual(store.seenVersion(of: .notifications), 0)
        XCTAssertTrue(store.isEmpty)
    }

    func test_markSeen_roundTripsThroughUserDefaults() {
        store.markSeen(.welcome, version: 1)
        XCTAssertEqual(store.seenVersion(of: .welcome), 1)
        XCTAssertFalse(store.isEmpty)

        // A second store over the same defaults sees the same data.
        let rehydrated = OnboardingStepStore(userDefaults: userDefaults)
        XCTAssertEqual(rehydrated.seenVersion(of: .welcome), 1)
    }

    func test_markSeen_neverLowersVersion() {
        store.markSeen(.location, version: 3)
        store.markSeen(.location, version: 1)
        XCTAssertEqual(store.seenVersion(of: .location), 3)
    }

    func test_backfill_existingUser_marksLegacyStepsButNotNotifications() {
        XCTAssertTrue(store.backfillIfNeeded(hasCurrentRegion: true))
        XCTAssertEqual(store.seenVersion(of: .welcome), 1)
        XCTAssertEqual(store.seenVersion(of: .location), 1)
        XCTAssertEqual(store.seenVersion(of: .region), 1)
        XCTAssertEqual(store.seenVersion(of: .done), 1)
        XCTAssertEqual(store.seenVersion(of: .notifications), 0)
        XCTAssertEqual(store.seenVersion(of: .migration), 0)
    }

    func test_backfill_newUser_doesNothing() {
        XCTAssertFalse(store.backfillIfNeeded(hasCurrentRegion: false))
        XCTAssertTrue(store.isEmpty)
    }

    func test_backfill_nonEmptyStore_neverRunsAgain() {
        store.markSeen(.welcome, version: 1)
        XCTAssertFalse(store.backfillIfNeeded(hasCurrentRegion: true))
        XCTAssertEqual(store.seenVersion(of: .region), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
scripts/generate_project OneBusAway
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: build FAILS with "cannot find 'OnboardingStepStore' in scope" (compile failure is the failing state for a new type; use `set -o pipefail` so `tail` doesn't mask the exit code).

- [ ] **Step 3: Write the implementation**

```swift
//
//  OnboardingStepStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Identifies each onboarding step. The raw value is the persistence key, so never rename cases.
public enum OnboardingStepID: String, CaseIterable, Sendable {
    case migration
    case welcome
    case location
    case region
    case notifications
    case done
}

/// Persists which onboarding steps a user has seen, and at what version.
///
/// A step is re-shown when its registry version exceeds the seen version. Steps mark
/// themselves seen at their own completion point (see `OnboardingFlowView`), not on display.
@MainActor
public final class OnboardingStepStore {
    static let userDefaultsKey = "OBAOnboardingSeenStepVersions"

    /// Steps that conceptually existed before the registry shipped. An existing user
    /// (identified by having a selected region) is treated as having seen these at v1,
    /// so the only step they match is whatever is *not* in this set — initially `.notifications`.
    /// Future steps need no change here: they are simply never backfilled.
    static let backfilledStepIDs: [OnboardingStepID] = [.welcome, .location, .region, .done]

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    private var seenVersions: [String: Int] {
        get { (userDefaults.dictionary(forKey: Self.userDefaultsKey) as? [String: Int]) ?? [:] }
        set { userDefaults.set(newValue, forKey: Self.userDefaultsKey) }
    }

    public var isEmpty: Bool {
        seenVersions.isEmpty
    }

    public func seenVersion(of id: OnboardingStepID) -> Int {
        seenVersions[id.rawValue] ?? 0
    }

    public func markSeen(_ id: OnboardingStepID, version: Int) {
        guard version > seenVersion(of: id) else { return }
        seenVersions[id.rawValue] = version
    }

    /// One-time seeding for users who onboarded before the registry existed.
    /// Runs only when the store has never recorded anything and a region is already selected.
    @discardableResult
    public func backfillIfNeeded(hasCurrentRegion: Bool) -> Bool {
        guard isEmpty, hasCurrentRegion else { return false }
        for id in Self.backfilledStepIDs {
            markSeen(id, version: 1)
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/OnboardingStepStoreTests -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`, 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Onboarding/Flow/OnboardingStepStore.swift OBAKitTests/Onboarding/OnboardingStepStoreTests.swift
git commit -m "Add OnboardingStepStore with seen-version tracking and existing-user backfill"
```

---

### Task 2: Step registry, environment, and flow computation

**Files:**
- Create: `OBAKit/Onboarding/Flow/OnboardingStep.swift`
- Create: `OBAKit/Onboarding/Flow/OnboardingRegistry.swift`
- Create: `OBAKitTests/Onboarding/OnboardingRegistryTests.swift`

**Interfaces:**
- Consumes: `OnboardingStepID`, `OnboardingStepStore` (Task 1).
- Produces:
  - `public struct OnboardingEnvironment: Sendable` — memberwise-initializable snapshot: `hasDataToMigrate`, `shouldPerformMigration`, `hasCurrentRegion`, `locationAuthorizationDetermined`, `notificationAuthorizationDetermined`, `isPushServiceConfigured` (all `Bool`), plus `static func current(application: Application) async -> OnboardingEnvironment`.
  - `public struct OnboardingStep: Identifiable, Sendable` — `id: OnboardingStepID`, `weight: Int`, `version: Int`, `tracksSeen: Bool`, `isEligible: @Sendable (OnboardingEnvironment) -> Bool`.
  - `public enum OnboardingRegistry` — `static let steps: [OnboardingStep]`, `@MainActor static func flow(environment:store:) -> [OnboardingStep]`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  OnboardingRegistryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit

@MainActor
final class OnboardingRegistryTests: XCTestCase {
    private var store: OnboardingStepStore!

    override func setUp() {
        super.setUp()
        store = OnboardingStepStore(userDefaults: UserDefaults(suiteName: "OnboardingRegistryTests-\(UUID().uuidString)")!)
    }

    /// Environment helper: a brand-new install with everything available.
    private func newUserEnvironment() -> OnboardingEnvironment {
        OnboardingEnvironment(
            hasDataToMigrate: false,
            shouldPerformMigration: false,
            hasCurrentRegion: false,
            locationAuthorizationDetermined: false,
            notificationAuthorizationDetermined: false,
            isPushServiceConfigured: true)
    }

    private func flowIDs(_ environment: OnboardingEnvironment) -> [OnboardingStepID] {
        OnboardingRegistry.flow(environment: environment, store: store).map(\.id)
    }

    func test_newUser_getsFullOrderedFlow() {
        XCTAssertEqual(flowIDs(newUserEnvironment()), [.welcome, .location, .region, .notifications, .done])
    }

    func test_migratingUser_getsMigrationFirst() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        XCTAssertEqual(flowIDs(env), [.migration, .welcome, .location, .region, .notifications, .done])
    }

    func test_backfilledExistingUser_getsExactlyNotifications() {
        var env = newUserEnvironment()
        env.hasCurrentRegion = true
        store.backfillIfNeeded(hasCurrentRegion: true)
        XCTAssertEqual(flowIDs(env), [.notifications])
    }

    func test_noPushProvider_hidesNotificationsStep() {
        var env = newUserEnvironment()
        env.isPushServiceConfigured = false
        XCTAssertEqual(flowIDs(env), [.welcome, .location, .region, .done])
    }

    func test_determinedNotificationPermission_hidesNotificationsStep() {
        var env = newUserEnvironment()
        env.notificationAuthorizationDetermined = true
        XCTAssertEqual(flowIDs(env), [.welcome, .location, .region, .done])
    }

    func test_determinedLocationPermission_hidesLocationStep() {
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = true
        XCTAssertEqual(flowIDs(env), [.welcome, .region, .notifications, .done])
    }

    func test_versionBump_reshowsOnlyThatStep() {
        store.backfillIfNeeded(hasCurrentRegion: true)
        store.markSeen(.notifications, version: 1)
        var env = newUserEnvironment()
        env.hasCurrentRegion = true

        XCTAssertEqual(flowIDs(env), [])

        // Simulate a future release bumping the location step to v2.
        let bumped = OnboardingRegistry.steps.map { step in
            step.id == .location
                ? OnboardingStep(id: step.id, weight: step.weight, version: 2, tracksSeen: step.tracksSeen, isEligible: step.isEligible)
                : step
        }
        let flow = OnboardingRegistry.flow(steps: bumped, environment: env, store: store)
        XCTAssertEqual(flow.map(\.id), [.location])
    }

    func test_migration_ignoresSeenState() {
        var env = newUserEnvironment()
        env.hasDataToMigrate = true
        env.shouldPerformMigration = true
        store.markSeen(.migration, version: 99)
        XCTAssertTrue(flowIDs(env).contains(.migration))
    }

    func test_allowOnceReversion_stepSeenSoNotReshown() {
        // "Allow Once" reverts location auth to .notDetermined after use, but a seen step stays hidden.
        var env = newUserEnvironment()
        env.locationAuthorizationDetermined = false
        store.markSeen(.location, version: 1)
        XCTAssertFalse(flowIDs(env).contains(.location))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the same build-for-testing command as Task 1 Step 2.
Expected: FAILS with "cannot find 'OnboardingRegistry' in scope".

- [ ] **Step 3: Write the implementation**

`OBAKit/Onboarding/Flow/OnboardingStep.swift`:

```swift
//
//  OnboardingStep.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UserNotifications

/// A snapshot of the app state that onboarding eligibility predicates run against.
/// Pure data so the flow computation is synchronous and unit-testable; the async
/// gathering (notification settings) happens once in `current(application:)`.
public struct OnboardingEnvironment: Sendable {
    public var hasDataToMigrate: Bool
    public var shouldPerformMigration: Bool
    public var hasCurrentRegion: Bool
    public var locationAuthorizationDetermined: Bool
    public var notificationAuthorizationDetermined: Bool
    public var isPushServiceConfigured: Bool

    public init(
        hasDataToMigrate: Bool,
        shouldPerformMigration: Bool,
        hasCurrentRegion: Bool,
        locationAuthorizationDetermined: Bool,
        notificationAuthorizationDetermined: Bool,
        isPushServiceConfigured: Bool
    ) {
        self.hasDataToMigrate = hasDataToMigrate
        self.shouldPerformMigration = shouldPerformMigration
        self.hasCurrentRegion = hasCurrentRegion
        self.locationAuthorizationDetermined = locationAuthorizationDetermined
        self.notificationAuthorizationDetermined = notificationAuthorizationDetermined
        self.isPushServiceConfigured = isPushServiceConfigured
    }

    @MainActor
    public static func current(application: Application) async -> OnboardingEnvironment {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return OnboardingEnvironment(
            hasDataToMigrate: application.hasDataToMigrate,
            shouldPerformMigration: application.shouldPerformMigration,
            hasCurrentRegion: application.regionsService.currentRegion != nil,
            locationAuthorizationDetermined: application.locationService.authorizationStatus != .notDetermined,
            notificationAuthorizationDetermined: settings.authorizationStatus != .notDetermined,
            isPushServiceConfigured: application.pushService != nil)
    }
}

/// One entry in the onboarding registry.
public struct OnboardingStep: Identifiable, Sendable {
    public let id: OnboardingStepID
    /// Sort key. Lower weights show earlier. Leave gaps so future steps can slot in.
    public let weight: Int
    /// Bump to re-show a changed step to everyone who saw an older version.
    public let version: Int
    /// When false, the seen-store is ignored and `isEligible` alone governs
    /// re-prompting (used by migration, which re-prompts until it succeeds).
    public let tracksSeen: Bool
    public let isEligible: @Sendable (OnboardingEnvironment) -> Bool

    public init(id: OnboardingStepID, weight: Int, version: Int, tracksSeen: Bool = true, isEligible: @escaping @Sendable (OnboardingEnvironment) -> Bool) {
        self.id = id
        self.weight = weight
        self.version = version
        self.tracksSeen = tracksSeen
        self.isEligible = isEligible
    }
}
```

`OBAKit/Onboarding/Flow/OnboardingRegistry.swift`:

```swift
//
//  OnboardingRegistry.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The ordered registry of onboarding steps. The flow shown to a user is this list
/// filtered by eligibility and what they haven't seen yet, sorted by weight.
///
/// To add a step: append an entry here and add a matching case to `OnboardingFlowView`'s
/// step switch. Existing users will see the new step by itself on their next launch.
public enum OnboardingRegistry {
    public static let steps: [OnboardingStep] = [
        OnboardingStep(id: .migration, weight: 5, version: 1, tracksSeen: false) {
            $0.hasDataToMigrate && $0.shouldPerformMigration
        },
        OnboardingStep(id: .welcome, weight: 10, version: 1) { _ in true },
        OnboardingStep(id: .location, weight: 20, version: 1) {
            !$0.locationAuthorizationDetermined
        },
        OnboardingStep(id: .region, weight: 30, version: 1) { _ in true },
        OnboardingStep(id: .notifications, weight: 40, version: 1) {
            $0.isPushServiceConfigured && !$0.notificationAuthorizationDetermined
        },
        OnboardingStep(id: .done, weight: 99, version: 1) { _ in true }
    ]

    @MainActor
    public static func flow(
        steps: [OnboardingStep] = Self.steps,
        environment: OnboardingEnvironment,
        store: OnboardingStepStore
    ) -> [OnboardingStep] {
        steps
            .filter { step in
                guard step.isEligible(environment) else { return false }
                guard step.tracksSeen else { return true }
                return store.seenVersion(of: step.id) < step.version
            }
            .sorted { $0.weight < $1.weight }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/OnboardingRegistryTests -only-testing:OBAKitTests/OnboardingStepStoreTests -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`, 15 tests passing.

Note: if `Application.pushService`, `Application.hasDataToMigrate`, or `LocationService.authorizationStatus` produce access-level errors in `OnboardingEnvironment.current`, check the actual declarations (`OBAKit/Orchestration/Application.swift`, `OBAKitCore/Location/Location/LocationService.swift:128`) — all three exist but confirm their exact spelling rather than renaming anything.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Onboarding/Flow/ OBAKitTests/Onboarding/OnboardingRegistryTests.swift
git commit -m "Add onboarding step registry with eligibility and seen-version flow computation"
```

---

### Task 3: Shared scaffold (progress bar, hero circle, button dock)

**Files:**
- Create: `OBAKit/Onboarding/Views/OnboardingScaffold.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure SwiftUI).
- Produces (used by every screen in Tasks 4–7):
  - `struct OnboardingHeroCircle: View` — `init(systemImageName: String)`; ringed accent-tinted circle.
  - `struct OnboardingScaffold<Content: View>: View` — `init(progress: (index: Int, total: Int)? = nil, badge: String? = nil, title: String, bodyText: String? = nil, footnote: String? = nil, primaryTitle: String, primaryAction: @escaping () -> Void, secondaryTitle: String? = nil, secondaryAction: (() -> Void)? = nil, @ViewBuilder content: () -> Content)`. Every screen passes `content` (at minimum the hero circle), so no `Content == EmptyView` convenience is needed — a generic default parameter would not compile anyway.

- [ ] **Step 1: Write the scaffold**

```swift
//
//  OnboardingScaffold.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The ringed hero circle used at the top of onboarding screens.
struct OnboardingHeroCircle: View {
    let systemImageName: String

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.08)).frame(width: 168, height: 168)
            Circle().fill(Color.accentColor.opacity(0.14)).frame(width: 132, height: 132)
            Circle().fill(Color.accentColor).frame(width: 108, height: 108)
            Image(systemName: systemImageName)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

/// Shared chrome for every onboarding step: segmented progress bar, centered
/// title/body, optional badge and footnote, and a fixed bottom button dock.
struct OnboardingScaffold<Content: View>: View {
    /// `nil` hides the progress bar (single-step mode for returning users).
    var progress: (index: Int, total: Int)?
    var badge: String?
    var title: String
    var bodyText: String?
    var footnote: String?
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        progress: (index: Int, total: Int)? = nil,
        badge: String? = nil,
        title: String,
        bodyText: String? = nil,
        footnote: String? = nil,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = progress
        self.badge = badge
        self.title = title
        self.bodyText = bodyText
        self.footnote = footnote
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let progress {
                HStack(spacing: 6) {
                    ForEach(0..<progress.total, id: \.self) { index in
                        Capsule()
                            .fill(index <= progress.index ? Color.accentColor : Color(.systemGray5))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(OBALoc("onboarding.progress.accessibility_label", value: "Onboarding progress", comment: "Accessibility label for the onboarding progress bar")))
                .accessibilityValue(Text("\(progress.index + 1)/\(progress.total)"))
            }

            ScrollView {
                VStack(spacing: 0) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .padding(.bottom, 14)
                    }

                    Text(title)
                        .font(.system(size: 32, weight: .heavy))
                        .multilineTextAlignment(.center)

                    if let bodyText {
                        Text(bodyText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 14)
                    }

                    content
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 6) {
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 10)
                }

                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.headline)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}

#if DEBUG
#Preview("Full flow step") {
    OnboardingScaffold(
        progress: (index: 0, total: 4),
        title: "Welcome to OneBusAway",
        bodyText: "Real-time arrivals for the buses, trains, and ferries you ride.",
        footnote: "Available in dozens of transit regions worldwide",
        primaryTitle: "Get Started",
        primaryAction: {}
    ) {
        OnboardingHeroCircle(systemImageName: "mappin")
            .padding(.vertical, 34)
    }
}

#Preview("Single step") {
    OnboardingScaffold(
        badge: "NEW",
        title: "Stay ahead of disruptions",
        primaryTitle: "Turn On Notifications",
        primaryAction: {},
        secondaryTitle: "Maybe Later",
        secondaryAction: {}
    ) {
        OnboardingHeroCircle(systemImageName: "bell.fill")
            .padding(.vertical, 22)
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **` (zero new warnings — the concurrency ratchet is enforcing).

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Views/OnboardingScaffold.swift
git commit -m "Add shared onboarding scaffold, progress bar, and hero circle"
```

---

### Task 4: Welcome and Done screens

**Files:**
- Create: `OBAKit/Onboarding/Views/OnboardingWelcomeView.swift`
- Create: `OBAKit/Onboarding/Views/OnboardingDoneView.swift`

**Interfaces:**
- Consumes: `OnboardingScaffold`, `OnboardingHeroCircle` (Task 3).
- Produces (consumed by `OnboardingFlowView` in Task 8):
  - `struct OnboardingWelcomeView: View` — `init(progress: (index: Int, total: Int)?, advance: @escaping () -> Void)`.
  - `struct OnboardingDoneView: View` — `init(progress: (index: Int, total: Int)?, regionName: String?, locationEnabled: Bool, advance: @escaping () -> Void)`. Fetches notification-auth state itself in `.task`.

- [ ] **Step 1: Write both screens**

`OBAKit/Onboarding/Views/OnboardingWelcomeView.swift`:

```swift
//
//  OnboardingWelcomeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// First-run brand moment. Marked seen on "Get Started".
struct OnboardingWelcomeView: View {
    var progress: (index: Int, total: Int)?
    var advance: () -> Void

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: String(format: OBALoc("onboarding.welcome.title_fmt", value: "Welcome to %@", comment: "Title of the first onboarding screen; the argument is the app name"), Bundle.main.appName),
            bodyText: OBALoc("onboarding.welcome.body", value: "Real-time arrivals for the buses, trains, and ferries you ride — built by transit riders, free and open source.", comment: "Body of the first onboarding screen"),
            footnote: OBALoc("onboarding.welcome.footnote", value: "Available in dozens of transit regions worldwide", comment: "Footnote of the first onboarding screen"),
            primaryTitle: OBALoc("onboarding.welcome.primary_button", value: "Get Started", comment: "Primary button on the first onboarding screen"),
            primaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "mappin")
                .padding(.vertical, 34)
        }
    }
}
```

`OBAKit/Onboarding/Views/OnboardingDoneView.swift`:

```swift
//
//  OnboardingDoneView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UserNotifications

/// Final recap screen. Rows reflect the user's actual choices.
struct OnboardingDoneView: View {
    var progress: (index: Int, total: Int)?
    var regionName: String?
    var locationEnabled: Bool
    var advance: () -> Void

    @State private var alertsEnabled = false

    private var onLabel: String { OBALoc("onboarding.done.value_on", value: "On", comment: "Recap value for an enabled setting") }
    private var offLabel: String { OBALoc("onboarding.done.value_off", value: "Off", comment: "Recap value for a disabled setting") }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.done.title", value: "You're all set", comment: "Title of the final onboarding screen"),
            bodyText: regionName.map {
                String(format: OBALoc("onboarding.done.body_fmt", value: "%@ is ready. Let's find your bus.", comment: "Body of the final onboarding screen; the argument is a region name"), $0)
            },
            primaryTitle: OBALoc("onboarding.done.primary_button", value: "Start Exploring", comment: "Primary button on the final onboarding screen"),
            primaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "checkmark")
                .padding(.vertical, 30)

            VStack(spacing: 0) {
                recapRow(
                    label: OBALoc("onboarding.done.region_row", value: "Region", comment: "Recap row label for the chosen region"),
                    value: regionName ?? offLabel)
                Divider()
                recapRow(
                    label: OBALoc("onboarding.done.location_row", value: "Location", comment: "Recap row label for location permission"),
                    value: locationEnabled ? onLabel : offLabel)
                Divider()
                recapRow(
                    label: OBALoc("onboarding.done.alerts_row", value: "Alerts", comment: "Recap row label for notification permission"),
                    value: alertsEnabled ? onLabel : offLabel)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(.top, 10)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            alertsEnabled = settings.authorizationStatus == .authorized
        }
    }

    private func recapRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }
}
```

- [ ] **Step 2: Build to verify both compile**

Same command as Task 3 Step 2. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Views/OnboardingWelcomeView.swift OBAKit/Onboarding/Views/OnboardingDoneView.swift
git commit -m "Add onboarding welcome and recap screens"
```

---

### Task 5: Location screen

**Files:**
- Create: `OBAKit/Onboarding/Views/OnboardingLocationView.swift`

**Interfaces:**
- Consumes: `OnboardingScaffold`, `OnboardingHeroCircle` (Task 3); `RegionProvider` (existing, `OBAKit/Onboarding/RegionPicker/RegionProvider.swift`); `\.coreApplication` environment (existing).
- Produces: `struct OnboardingLocationView<Provider: RegionProvider>: View` — `init(progress: (index: Int, total: Int)?, regionProvider: Provider, advance: @escaping () -> Void)`. Same underlying behavior as the old `RegionPickerLocationAuthorizationView`: primary sets `automaticallySelectRegion = true` + `requestInUseAuthorization()`; secondary sets it `false`. Both then `advance()` (the caller marks seen — spec: either button counts as seen).

- [ ] **Step 1: Write the screen**

```swift
//
//  OnboardingLocationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Primes the user before the OS location prompt. Replaces `RegionPickerLocationAuthorizationView`
/// in the onboarding flow (spec decision: two-button layout kept deliberately despite the HIG
/// one-button guidance for pre-alert screens; declining marks the step seen forever).
struct OnboardingLocationView<Provider: RegionProvider>: View {
    var progress: (index: Int, total: Int)?
    @ObservedObject var regionProvider: Provider
    var advance: () -> Void

    @Environment(\.coreApplication) var application

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.location.title", value: "See transit around you", comment: "Title of the location onboarding screen"),
            footnote: String(format: OBALoc("onboarding.location.footnote_fmt", value: "%@ only uses your location while the app is open. Change this anytime in Settings.", comment: "Footnote of the location onboarding screen; the argument is the app name"), Bundle.main.appName),
            primaryTitle: OBALoc("onboarding.location.primary_button", value: "Use My Location", comment: "Button the user taps to grant access to their location."),
            primaryAction: {
                regionProvider.automaticallySelectRegion = true
                application.locationService.requestInUseAuthorization()
                advance()
            },
            secondaryTitle: OBALoc("onboarding.location.secondary_button", value: "Not Now", comment: "Button the user can tap on to decline access to their location."),
            secondaryAction: {
                regionProvider.automaticallySelectRegion = false
                advance()
            }
        ) {
            OnboardingHeroCircle(systemImageName: "location.fill")
                .padding(.vertical, 30)

            VStack(alignment: .leading, spacing: 14) {
                benefitRow(
                    heading: OBALoc("onboarding.location.benefit_nearby_title", value: "See nearby stops", comment: "Heading for a benefit of granting location access"),
                    detail: OBALoc("onboarding.location.benefit_nearby_body", value: "Buses and trains around you, ranked by distance.", comment: "Detail for the nearby-stops benefit"))
                benefitRow(
                    heading: OBALoc("onboarding.location.benefit_map_title", value: "Center the map on you", comment: "Heading for a benefit of granting location access"),
                    detail: OBALoc("onboarding.location.benefit_map_body", value: "Open straight to your surroundings — no searching.", comment: "Detail for the map-centering benefit"))
            }
            .padding(.top, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func benefitRow(heading: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(Circle().fill(Color.accentColor).frame(width: 8, height: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.callout.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Same command as Task 3 Step 2. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Views/OnboardingLocationView.swift
git commit -m "Add onboarding location priming screen"
```

---

### Task 6: Region screen

**Files:**
- Create: `OBAKit/Onboarding/Views/OnboardingRegionView.swift`

**Interfaces:**
- Consumes: `OnboardingScaffold` (Task 3); existing `RegionProvider`, `RegionPickerView(regionProvider:dismissBlock:)`, `Region` (`name`, `distanceFrom(location:)` at `OBAKitCore/Models/Region.swift:495`).
- Produces: `struct OnboardingRegionView<Provider: RegionProvider>: View` — `init(progress: (index: Int, total: Int)?, regionProvider: Provider, advance: @escaping () -> Void)`. Calls `advance()` only after a region is confirmed (spec: region marks seen only on confirmation). "See all regions" pushes the existing `RegionPickerView` via `NavigationLink` (the flow container provides a `NavigationStack`, Task 8).

- [ ] **Step 1: Write the screen**

```swift
//
//  OnboardingRegionView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Region selection: an auto-detected card with a short list fallback.
/// "See all regions" pushes the existing full `RegionPickerView` (custom regions live there).
struct OnboardingRegionView<Provider: RegionProvider>: View {
    var progress: (index: Int, total: Int)?
    @ObservedObject var regionProvider: Provider
    var advance: () -> Void

    @State private var selectedRegion: Region?
    @State private var error: Error?
    @State private var isSettingRegion = false

    /// Nearest region to the user, or their already-auto-selected region.
    private var detectedRegion: Region? {
        if let current = regionProvider.currentRegion { return current }
        guard let location = regionProvider.currentLocation else { return nil }
        return regionProvider.allRegions.min {
            $0.distanceFrom(location: location) < $1.distanceFrom(location: location)
        }
    }

    private var shortList: [Region] {
        regionProvider.allRegions
            .filter { $0.id != (selectedRegion ?? detectedRegion)?.id }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        OnboardingScaffold(
            progress: progress,
            title: OBALoc("onboarding.region.title", value: "Your region", comment: "Title of the region onboarding screen"),
            bodyText: detectedRegion == nil
                ? OBALoc("onboarding.region.body_no_location", value: "Choose the transit network you ride.", comment: "Body of the region onboarding screen when no location is available")
                : OBALoc("onboarding.region.body", value: "We found the transit network closest to you.", comment: "Body of the region onboarding screen"),
            primaryTitle: OBALoc("onboarding.region.primary_button", value: "Continue", comment: "Primary button on the region onboarding screen"),
            primaryAction: confirmSelection
        ) {
            VStack(spacing: 0) {
                if let region = selectedRegion ?? detectedRegion {
                    selectedCard(for: region)
                        .padding(.top, 22)
                }

                if !shortList.isEmpty {
                    Text(OBALoc("onboarding.region.other_header", value: "Or choose another", comment: "Header above the alternate-regions list").uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(shortList, id: \.id) { region in
                            Button {
                                selectedRegion = region
                            } label: {
                                Text(region.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                            if region.id != shortList.last?.id { Divider() }
                        }
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                NavigationLink {
                    RegionPickerView(regionProvider: regionProvider, dismissBlock: advance)
                } label: {
                    Text(OBALoc("onboarding.region.see_all_button", value: "See all regions", comment: "Link to the full region picker"))
                        .font(.headline)
                }
                .padding(.top, 20)
            }
        }
        .task {
            try? await regionProvider.refreshRegions()
        }
        .disabled(isSettingRegion)
        .errorAlert(error: $error)
    }

    private func selectedCard(for region: Region) -> some View {
        VStack(spacing: 0) {
            // Live map preview (spec: preferred over MKMapSnapshotter — adapts to dark
            // mode automatically and can draw the service-area overlay).
            RegionPickerMap(mapRect: .constant(region.serviceRect), mapHeight: 108)
                .frame(height: 108)
                .clipped()
            cardFooter(for: region)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func cardFooter(for region: Region) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(OBALoc("onboarding.region.detected_label", value: "Detected near you", comment: "Label on the detected-region card").uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(region.name)
                    .font(.title3.weight(.bold))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(16)
    }

    private func confirmSelection() {
        guard let region = selectedRegion ?? detectedRegion else { return }
        isSettingRegion = true
        Task {
            defer { isSettingRegion = false }
            do {
                try await regionProvider.setCurrentRegion(to: region)
                advance()
            } catch {
                self.error = error
            }
        }
    }
}
```

Note: `.errorAlert(error:)` — check `OBAKit/Extensions/SwiftUIExtensions.swift` for an existing error-alert helper before writing one; `RegionPickerView` already presents errors, follow whatever pattern it uses (if none exists, use `.alert("Error", isPresented:presenting:)` inline).

- [ ] **Step 2: Build to verify it compiles**

Same command as Task 3 Step 2. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Views/OnboardingRegionView.swift
git commit -m "Add onboarding region screen with detected-region card"
```

---

### Task 7: Notifications screen

**Files:**
- Create: `OBAKit/Onboarding/Views/OnboardingNotificationsView.swift`

**Interfaces:**
- Consumes: `OnboardingScaffold`, `OnboardingHeroCircle` (Task 3).
- Produces: `struct OnboardingNotificationsView: View` — `init(progress: (index: Int, total: Int)?, isSingleStep: Bool, advance: @escaping () -> Void)`. Single-step mode shows the NEW badge and "Maybe Later"; full-flow mode shows "Not Now" + footnote. `advance()` is called after the OS prompt resolves (either outcome) or on decline — both mark seen (spec: one pitch, ever).

- [ ] **Step 1: Write the screen**

```swift
//
//  OnboardingNotificationsView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import UserNotifications
import OBAKitCore

/// Pitches region-wide service-alert notifications, then triggers the OS permission prompt.
///
/// Requests authorization directly (not via `PushService.pushID()`, whose callback never fires
/// on denial and would hang the flow). On grant it calls `registerForRemoteNotifications()`;
/// the resulting device token still flows through the existing AppDelegate → PushService wiring.
struct OnboardingNotificationsView: View {
    var progress: (index: Int, total: Int)?
    var isSingleStep: Bool
    var advance: () -> Void

    @State private var isRequesting = false

    private struct ExampleAlert: Identifiable {
        let id = UUID()
        let color: Color
        let text: String
    }

    private var exampleAlerts: [ExampleAlert] {
        [
            ExampleAlert(color: .red, text: OBALoc("onboarding.notifications.example_storm", value: "Winter storm — reduced service on 12 routes", comment: "Example service alert shown on the notifications onboarding screen")),
            ExampleAlert(color: .blue, text: OBALoc("onboarding.notifications.example_ferry", value: "Ferry delays: up to 40 minute waits", comment: "Example service alert shown on the notifications onboarding screen")),
            ExampleAlert(color: .orange, text: OBALoc("onboarding.notifications.example_event", value: "Big game today: extra trains to the stadium", comment: "Example service alert shown on the notifications onboarding screen"))
        ]
    }

    var body: some View {
        OnboardingScaffold(
            progress: isSingleStep ? nil : progress,
            badge: isSingleStep ? OBALoc("onboarding.notifications.new_badge", value: "NEW", comment: "Badge shown when the notifications step appears alone for existing users") : nil,
            title: OBALoc("onboarding.notifications.title", value: "Stay ahead of disruptions", comment: "Title of the notifications onboarding screen"),
            bodyText: OBALoc("onboarding.notifications.body", value: "Get notified about region-wide service alerts — ice storms, flooding, and major events that change how transit runs.", comment: "Body of the notifications onboarding screen"),
            footnote: isSingleStep ? nil : OBALoc("onboarding.notifications.footnote", value: "Only major, region-wide alerts. No spam — you control the rest in Settings.", comment: "Footnote of the notifications onboarding screen"),
            primaryTitle: OBALoc("onboarding.notifications.primary_button", value: "Turn On Notifications", comment: "Primary button on the notifications onboarding screen"),
            primaryAction: requestAuthorization,
            secondaryTitle: isSingleStep
                ? OBALoc("onboarding.notifications.maybe_later_button", value: "Maybe Later", comment: "Decline button when the notifications step appears alone")
                : OBALoc("onboarding.notifications.not_now_button", value: "Not Now", comment: "Decline button on the notifications onboarding screen"),
            secondaryAction: advance
        ) {
            OnboardingHeroCircle(systemImageName: "bell.fill")
                .padding(.vertical, 22)

            VStack(spacing: 9) {
                ForEach(exampleAlerts) { alert in
                    HStack(spacing: 11) {
                        Circle().fill(alert.color).frame(width: 9, height: 9)
                        Text(alert.text)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13))
                }
            }
            .padding(.top, 22)
        }
        .disabled(isRequesting)
    }

    private func requestAuthorization() {
        isRequesting = true
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                Logger.error("Onboarding notification authorization failed: \(error)")
            }
            isRequesting = false
            advance()
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Same command as Task 3 Step 2. Expected: `** BUILD SUCCEEDED **`. (If `Logger` is ambiguous or scoped differently in OBAKit, match the logging call used in `OBACloudPushService.swift:109`.)

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Views/OnboardingNotificationsView.swift
git commit -m "Add onboarding notifications pitch screen"
```

---

### Task 8: Flow container view

**Files:**
- Create: `OBAKit/Onboarding/Flow/OnboardingFlowView.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–7, plus existing `RegionPickerCoordinator`, `DataMigrationView(dismissBlock:)`, `\.coreApplication`.
- Produces (consumed by the controller in Task 9): `struct OnboardingFlowView: View` — `init(application: Application, steps: [OnboardingStep], store: OnboardingStepStore, onFinished: @escaping () -> Void)`.

- [ ] **Step 1: Write the container**

```swift
//
//  OnboardingFlowView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Renders a computed onboarding flow. Advancing past a step marks it seen (unless the
/// step opted out, or the caller passes `markSeen: false`); finishing the last step
/// calls `onFinished`, which hands control back to the app's root UI.
struct OnboardingFlowView: View {
    let application: Application
    let steps: [OnboardingStep]
    let store: OnboardingStepStore
    let onFinished: () -> Void

    @StateObject private var regionPickerCoordinator: RegionPickerCoordinator
    @State private var index = 0

    init(application: Application, steps: [OnboardingStep], store: OnboardingStepStore, onFinished: @escaping () -> Void) {
        self.application = application
        self.steps = steps
        self.store = store
        self.onFinished = onFinished
        self._regionPickerCoordinator = StateObject(wrappedValue: RegionPickerCoordinator(regionsService: application.regionsService))
    }

    /// Single-step mode: no progress bar, NEW badge, "Maybe Later" copy.
    private var isSingleStep: Bool { steps.count == 1 }

    private var progress: (index: Int, total: Int)? {
        isSingleStep ? nil : (index: index, total: steps.count)
    }

    var body: some View {
        NavigationStack {
            stepView(for: steps[index])
                .navigationBarHidden(true)
        }
        .environment(\.coreApplication, application)
        .id(steps[index].id)
        .animation(.default, value: index)
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step.id {
        case .migration:
            DataMigrationView(dismissBlock: { advance(markSeen: false) })
        case .welcome:
            OnboardingWelcomeView(progress: progress, advance: { advance() })
        case .location:
            OnboardingLocationView(progress: progress, regionProvider: regionPickerCoordinator, advance: { advance() })
        case .region:
            OnboardingRegionView(progress: progress, regionProvider: regionPickerCoordinator, advance: { advance() })
        case .notifications:
            OnboardingNotificationsView(progress: progress, isSingleStep: isSingleStep, advance: { advance() })
        case .done:
            OnboardingDoneView(
                progress: progress,
                regionName: regionPickerCoordinator.currentRegion?.name,
                locationEnabled: application.locationService.isLocationUseAuthorized,
                advance: { advance() })
        }
    }

    private func advance(markSeen: Bool = true) {
        let step = steps[index]
        if markSeen && step.tracksSeen {
            store.markSeen(step.id, version: step.version)
        }

        if index + 1 < steps.count {
            index += 1
        } else {
            onFinished()
        }
    }
}
```

Note: `LocationService.isLocationUseAuthorized` — the exact property name is at `OBAKitCore/Location/Location/LocationService.swift:173` (a computed property checking `.authorizedWhenInUse || .authorizedAlways`); use whatever it is actually called there.

- [ ] **Step 2: Build to verify it compiles**

Same command as Task 3 Step 2. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add OBAKit/Onboarding/Flow/OnboardingFlowView.swift
git commit -m "Add onboarding flow container with seen-marking and single-step mode"
```

---

### Task 9: ObjC-visible controller, AppDelegate integration, delete old controllers

**Files:**
- Create: `OBAKit/Onboarding/Flow/OnboardingFlowController.swift`
- Modify: `Apps/OneBusAway/AppDelegate.m:100-114` (`applicationReloadRootInterface:`)
- Modify: `Apps/KiedyBus/AppDelegate.m:75-78` (`applicationReloadRootInterface:` — KiedyBus never presented onboarding before; this wires it up)
- Delete: `Apps/OneBusAway/Onboarding/OnboardingNavigationController.swift`, `Apps/KiedyBus/Onboarding/OnboardingNavigationController.swift` (and their now-empty `Onboarding/` directories)

**Interfaces:**
- Consumes: `OnboardingRegistry`, `OnboardingStepStore`, `OnboardingEnvironment`, `OnboardingFlowView` (Tasks 1, 2, 8).
- Produces (ObjC surface consumed by both AppDelegates):
  - `@objc(OBAOnboardingFlowController) public class OnboardingFlowController: UIViewController` with `@objc public var onFinished: (() -> Void)?`.
  - `@objc public static func evaluate(application: Application, completion: @escaping (OnboardingFlowController?) -> Void)` — computes the flow (backfill → environment → filter); calls back on the main queue with a controller, or `nil` when no onboarding is needed. ObjC selector: `evaluateWithApplication:completion:`.

- [ ] **Step 1: Write the controller**

```swift
//
//  OnboardingFlowController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// UIKit entry point for the onboarding flow. A plain `UIViewController` embedding a
/// `UIHostingController` child, because `UIHostingController` subclasses can't be exposed
/// to Objective-C. Replaces `OnboardingNavigationController`.
///
/// Usage (from the app delegate's `applicationReloadRootInterface:`):
/// call ``evaluate(application:completion:)``; if the completion hands you a controller,
/// set its ``onFinished`` block and install it as the window's root view controller.
@objc(OBAOnboardingFlowController)
public class OnboardingFlowController: UIViewController {
    /// Called on the main queue when the user completes the last step.
    @objc public var onFinished: (() -> Void)?

    private let application: Application
    private let steps: [OnboardingStep]
    private let store: OnboardingStepStore

    private static var testOnboarding: Bool {
        #if DEBUG
        let envVar = ProcessInfo.processInfo.environment["TEST_ONBOARDING"] ?? "0"
        return (envVar as NSString).boolValue
        #else
        return false
        #endif
    }

    /// Computes the onboarding flow for this launch and calls back on the main queue with
    /// a ready-to-present controller, or `nil` if no onboarding is needed.
    ///
    /// Also performs the one-time existing-user backfill: users with a selected region but
    /// no seen-step record are marked as having seen the pre-registry steps, so the only
    /// steps they can match are ones added after the registry shipped (e.g. notifications).
    @objc public static func evaluate(application: Application, completion: @escaping (OnboardingFlowController?) -> Void) {
        Task { @MainActor in
            let store = OnboardingStepStore(userDefaults: application.userDefaults)
            store.backfillIfNeeded(hasCurrentRegion: application.regionsService.currentRegion != nil)

            let environment = await OnboardingEnvironment.current(application: application)
            var flow = OnboardingRegistry.flow(environment: environment, store: store)

            if testOnboarding {
                flow = OnboardingRegistry.steps
            }

            guard !flow.isEmpty else {
                completion(nil)
                return
            }

            completion(OnboardingFlowController(application: application, steps: flow, store: store))
        }
    }

    @MainActor
    init(application: Application, steps: [OnboardingStep], store: OnboardingStepStore) {
        self.application = application
        self.steps = steps
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let flowView = OnboardingFlowView(application: application, steps: steps, store: store) { [weak self] in
            self?.onFinished?()
        }

        let host = UIHostingController(rootView: flowView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}
```

Note: `application.userDefaults` — `Application`/`CoreApplication` exposes the app-group `UserDefaults` (check `OBAKit/Orchestration/Application.swift` for the exact property; it is widely used). If it turns out to be internal-only, use the same accessor `RegionsService` is constructed with.

- [ ] **Step 2: Update `Apps/OneBusAway/AppDelegate.m`**

Replace the body of `applicationReloadRootInterface:` (lines 100–114):

```objc
- (void)applicationReloadRootInterface:(OBAApplication*)application {
    void(^showRootController)(void) = ^{
        self.rootController = [OBAApplicationRootControllerFactory makeWithApplication:application];
        self.window.rootViewController = self.rootController;
    };

    [OBAOnboardingFlowController evaluateWithApplication:application completion:^(OBAOnboardingFlowController * _Nullable onboarding) {
        if (onboarding) {
            onboarding.onFinished = ^{
                showRootController();
                [UIView transitionWithView:self.window duration:0.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:nil completion:nil];
            };
            self.window.rootViewController = onboarding;
        } else {
            showRootController();
        }
    }];
}
```

(The window shows the launch screen for the few milliseconds the notification-settings fetch takes; this is during launch and imperceptible.)

- [ ] **Step 3: Update `Apps/KiedyBus/AppDelegate.m`**

Replace `applicationReloadRootInterface:` (lines 75–78) with the identical block from Step 2 (KiedyBus gains onboarding for the first time — its old `OnboardingNavigationController` copy was never referenced).

- [ ] **Step 4: Delete the old controllers and regenerate**

```bash
git rm -r Apps/OneBusAway/Onboarding Apps/KiedyBus/Onboarding
scripts/generate_project OneBusAway
```

Then search for stragglers — expect zero hits:
```bash
grep -rn "OnboardingNavigationController" --include='*.swift' --include='*.m' --include='*.h' --include='*.yml' . | grep -v docs/
```
If any `project.yml` references the deleted `Onboarding/` directories explicitly, remove those entries.

- [ ] **Step 5: Build both apps and run the full onboarding test suite**

```bash
set -o pipefail
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
scripts/generate_project KiedyBus
xcodebuild clean build -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
scripts/generate_project OneBusAway
```
Expected: `** BUILD SUCCEEDED **` for both apps; `** TEST SUCCEEDED **` for OBAKitTests.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Replace per-app onboarding controllers with shared registry-driven flow"
```

---

### Task 10: Localization, full verification, manual flow check

**Files:**
- Modify: `OBAKit/Strings/en.lproj/Localizable.strings` (via script)

**Interfaces:**
- Consumes: all prior tasks.
- Produces: shippable branch.

- [ ] **Step 1: Extract strings**

```bash
scripts/extract_strings
git diff --stat OBAKit/Strings
```
Expected: new `onboarding.*` keys appear in `en.lproj`. (Per project practice, en.lproj is regenerated from source; other locales get the new keys translated separately.)

- [ ] **Step 2: Run the complete test suite**

```bash
set -o pipefail
scripts/generate_project OneBusAway
xcodebuild build-for-testing -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project OBAKit.xcodeproj -scheme App -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -15
```
Expected: `** TEST SUCCEEDED **`, zero failures.

- [ ] **Step 3: Manual verification — first-run flow**

Run the app on the iPhone 17 Pro simulator with `TEST_ONBOARDING=1` in the scheme's environment (or via `xcrun simctl launch --terminate-running-first booted org.onebusaway.iphone --setenv TEST_ONBOARDING=1` — check the app's actual bundle ID in `Apps/OneBusAway/project.yml`). Verify: all six steps appear in weight order; progress bar advances; dark mode looks right (toggle Appearance in Simulator settings); completing hands off to the map with the flip transition.

- [ ] **Step 4: Manual verification — existing-user single step**

Without `TEST_ONBOARDING`: on a simulator where the app already has a region selected and notification permission is undetermined (`xcrun simctl privacy booted reset notifications org.onebusaway.iphone` resets it), relaunch. Verify: only the notifications screen appears, with NEW badge, no progress bar, "Maybe Later"; either button returns to the map; relaunching again goes straight to the map (step now seen).

- [ ] **Step 5: SwiftLint and commit**

```bash
scripts/swiftlint.sh
git add -A
git commit -m "Extract onboarding strings"
```
Expected: no new SwiftLint violations; final commit clean.
