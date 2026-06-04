# Wire up external surveys — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make external surveys (`type: external_survey`) actually open by wiring the already-tested `ExternalSurveyURLBuilder` into the live survey UI.

**Architecture:** `CoreApplication` conforms to `SurveyURLApplicationContext`; `SurveyService` (OBAKitCore) vends the builder and exposes `externalSurveyURL(for:stop:)`. A small `@MainActor ExternalSurveyLauncher` (OBAKit) builds the URL, opens it via `UIApplication.open`, and marks the survey completed **only on a successful open**. The `.externalSurvey` case in `SurveyViewController` and `SurveyCell` is replaced with a tappable control that drives the launcher. The open seam stays in OBAKit because OBAKitCore must remain application-extension-safe (`UIApplication.shared` is unavailable in extensions). To avoid a `CoreApplication ↔ SurveyService ↔ builder` retain cycle, the context protocol becomes class-bound and is held weakly.

**Tech Stack:** Swift 5.x, iOS 17+, UIKit, Eureka (forms), FloatingPanel (bottom sheet), XCTest + Nimble.

**Spec:** `docs/superpowers/specs/2026-06-02-wire-external-surveys-design.md`

---

## File Structure

**Modify (OBAKitCore):**
- `OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift` — make protocol `: AnyObject`.
- `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift` — hold `application` `weak`.
- `OBAKitCore/Surveys/Service/SurveyService.swift` — add weak `application`, vend builder, add `externalSurveyURL(for:stop:)`.
- `OBAKitCore/Orchestration/CoreApplication.swift` — conform to the context, pass `self` into `SurveyService` (2 sites).

**Modify (OBAKit):**
- `OBAKit/Surveys/SurveyDisplayManager.swift`, `OBAKit/Surveys/SurveyBottomSheetController.swift`, `OBAKit/Surveys/SurveyViewController.swift` — thread `stop: Stop?`.
- `OBAKit/Surveys/SurveyViewController.swift` — tappable `.externalSurvey` row + launcher.
- `OBAKit/Surveys/SurveyCell.swift` — tappable hero `.externalSurvey` button.
- `OBAKit/Surveys/SurveyStopListItem.swift` — `onOpenExternalSurvey` closure.
- `OBAKit/Stops/StopViewController.swift` — pass `stop`, handle hero open.

**Create (OBAKit):**
- `OBAKit/Surveys/ExternalSurveyLauncher.swift` — build + open + mark-completed unit.

**Create (tests):**
- `OBAKitTests/Modeling/Surveys Tests/SurveyServiceExternalURLTests.swift`
- `OBAKitTests/Surveys/ExternalSurveyLauncherTests.swift`
- New test added to `OBAKitTests/Surveys/ExternalSurveyURLBuilderTests.swift` (weak-ref).

**Build/test commands (run from repo root):**
```bash
scripts/generate_project OneBusAway
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/<Class> -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Task 1: Make the context protocol class-bound and hold it weakly in the builder

Breaks the retain cycle described in the spec (§5). The protocol becomes `AnyObject` so the builder (and later `SurveyService`) can hold it `weak`.

**Files:**
- Modify: `OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift`
- Modify: `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift:16`, `:72-77`, `:94-99`
- Test: `OBAKitTests/Surveys/ExternalSurveyURLBuilderTests.swift`

- [ ] **Step 1: Write the failing test** (append inside `ExternalSurveyURLBuilderTests`, before `// MARK: - Helpers`)

```swift
// MARK: - Lifecycle

func test_builder_doesNotRetainApplicationContext() {
    var localContext: MockSurveyURLApplicationContext? = MockSurveyURLApplicationContext()
    localContext?.currentRegionIdentifier = 5
    let localBuilder = ExternalSurveyURLBuilder(
        userStore: userDefaultsStore,
        userID: "u",
        application: localContext!
    )
    weak var weakContext = localContext

    localContext = nil

    // If the builder held a strong reference, weakContext would still be non-nil.
    expect(weakContext).to(beNil())

    // And with the context gone, region_id resolves to nil instead of crashing.
    let survey = SurveysTestHelpers.makeSurvey(questions: [
        SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["region_id"])
    ])
    expect(self.queryValue(in: localBuilder.buildURL(for: survey, stop: nil), for: "region_id")).to(beNil())
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/ExternalSurveyURLBuilderTests/test_builder_doesNotRetainApplicationContext -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: FAIL — `weakContext` is still non-nil because the builder strongly retains `application`.

- [ ] **Step 3: Make the protocol class-bound**

In `OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift`, change the declaration:
```swift
public protocol SurveyURLApplicationContext: AnyObject {

    var currentRegionIdentifier: Int? { get }

    var currentCoordinate: CLLocationCoordinate2D? { get }

}
```

- [ ] **Step 4: Hold the reference weakly in the builder**

In `OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift`, change the stored property (line 16):
```swift
    private weak var application: SurveyURLApplicationContext?
```
Then update the two readers to use optional chaining:
```swift
    private func getRegionID() -> String? {
        guard let regionId = application?.currentRegionIdentifier else {
            return nil
        }
        return "\(regionId)"
    }
```
```swift
    private func getCurrentLocation() -> String? {
        guard let coordinate = application?.currentCoordinate else {
            return nil
        }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }
```
(The `init` still takes a non-optional `application` and assigns it to the weak var — no signature change.)

- [ ] **Step 5: Run the new test + the full builder suite to verify green**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/ExternalSurveyURLBuilderTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: PASS — the new lifecycle test passes and all existing builder tests still pass (the test class retains `applicationContext` for each method, so the weak reference stays valid during normal tests).

- [ ] **Step 6: Commit**

```bash
git add OBAKitCore/Surveys/Helper/SurveyURLApplicationContext.swift OBAKitCore/Surveys/Helper/ExternalSurveyURLBuilder.swift "OBAKitTests/Surveys/ExternalSurveyURLBuilderTests.swift"
git commit -m "Make SurveyURLApplicationContext class-bound; hold it weakly in builder (#1148)"
```

---

## Task 2: SurveyService vends the builder and exposes `externalSurveyURL(for:stop:)`

**Files:**
- Modify: `OBAKitCore/Surveys/Service/SurveyService.swift:31-50`
- Test: `OBAKitTests/Modeling/Surveys Tests/SurveyServiceExternalURLTests.swift` (create)

- [ ] **Step 1: Write the failing test** (create the file)

```swift
//
//  SurveyServiceExternalURLTests.swift
//  OBAKitTests
//

import XCTest
import Nimble
@testable import OBAKitCore

@MainActor
final class SurveyServiceExternalURLTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).exturl")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "test-user-123"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).exturl")
        super.tearDown()
    }

    func test_externalSurveyURL_wiresBuilder_appendingUserIDAndRegion() {
        context.currentRegionIdentifier = 7
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s", embeddedDataFields: ["user_id", "region_id"])
        ])

        let url = service.externalSurveyURL(for: survey, stop: nil)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []

        expect(items.first { $0.name == "user_id" }?.value).to(equal("test-user-123"))
        expect(items.first { $0.name == "region_id" }?.value).to(equal("7"))
    }

    func test_externalSurveyURL_returnsNil_whenNoContext() {
        let svc = SurveyService(apiService: nil, userDataStore: store, application: nil)
        let survey = SurveysTestHelpers.makeSurvey(questions: [
            SurveysTestHelpers.makeSurveyQuestion(url: "https://oba.co/s")
        ])
        expect(svc.externalSurveyURL(for: survey, stop: nil)).to(beNil())
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/SurveyServiceExternalURLTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: FAIL to compile — `SurveyService` has no `application:` init parameter and no `externalSurveyURL`.

- [ ] **Step 3: Add the context, builder, and method to `SurveyService`**

In `OBAKitCore/Surveys/Service/SurveyService.swift`, in the `// MARK: - Dependencies` section add:
```swift
    /// Context used to build external-survey URLs. Held weakly: the owning
    /// application is the long-lived object and must not be retained here
    /// (see spec §5). Read only on the main actor.
    public weak var application: SurveyURLApplicationContext?
```
Replace the initializer:
```swift
    public nonisolated init(apiService: RESTAPIService?, userDataStore: UserDataStore, application: SurveyURLApplicationContext? = nil) {
        self.apiService = apiService
        self.userDataStore = userDataStore
        self.application = application
    }
```
Add a new `// MARK: - External Surveys` section (e.g. just after the initializer):
```swift
    // MARK: - External Surveys

    /// Builds external-survey URLs. Lazily created so it can be replaced with a
    /// mock in tests; `nil` when no application context was provided.
    public lazy var externalSurveyURLBuilder: ExternalSurveyURLBuilderProtocol? = {
        guard let application else { return nil }
        return ExternalSurveyURLBuilder(
            userStore: userDataStore,
            userID: userDataStore.surveyUserIdentifier,
            application: application
        )
    }()

    /// Destination URL for an external survey, or `nil` if it cannot be built.
    public func externalSurveyURL(for survey: Survey, stop: Stop?) -> URL? {
        externalSurveyURLBuilder?.buildURL(for: survey, stop: stop)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/SurveyServiceExternalURLTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Surveys/Service/SurveyService.swift "OBAKitTests/Modeling/Surveys Tests/SurveyServiceExternalURLTests.swift"
git commit -m "SurveyService: vend external-survey URL builder + externalSurveyURL(for:stop:) (#1148)"
```

---

## Task 3: CoreApplication conforms to the context and injects itself into SurveyService

DI wiring. No new unit test — verified by `build-for-testing` and exercised end-to-end by the launcher tests (Task 5) via a mock context.

**Files:**
- Modify: `OBAKitCore/Orchestration/CoreApplication.swift:278`, `:283`, and add an extension.

- [ ] **Step 1: Confirm no existing `currentRegionIdentifier` member clashes**

Run:
```bash
grep -n 'currentRegionIdentifier\|import CoreLocation' OBAKitCore/Orchestration/CoreApplication.swift
```
Expected: no existing `currentRegionIdentifier` declaration. If `import CoreLocation` is absent, add it at the top of the file.

- [ ] **Step 2: Add the conformance extension**

At the end of `OBAKitCore/Orchestration/CoreApplication.swift` (file scope, after the class closing brace):
```swift
// MARK: - SurveyURLApplicationContext

extension CoreApplication: SurveyURLApplicationContext {
    public var currentRegionIdentifier: Int? {
        regionsService.currentRegion?.regionIdentifier
    }

    public var currentCoordinate: CLLocationCoordinate2D? {
        locationService.currentLocation?.coordinate
    }
}
```

- [ ] **Step 3: Pass `self` into both SurveyService construction sites**

Line ~278:
```swift
    public private(set) lazy var surveyService = SurveyService(apiService: apiService, userDataStore: userDefaultsStore, application: self)
```
Line ~283 (inside `refreshSurveysService()`):
```swift
            self.surveyService = SurveyService(apiService: self.apiService, userDataStore: self.userDefaultsStore, application: self)
```

- [ ] **Step 4: Build for testing to verify it compiles and existing survey tests pass**

Run:
```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test-without-building -only-testing:OBAKitTests/SurveyServiceTests -only-testing:OBAKitTests/SurveyServiceStateTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: build succeeds; existing SurveyService suites PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Orchestration/CoreApplication.swift
git commit -m "CoreApplication: conform to SurveyURLApplicationContext and inject into SurveyService (#1148)"
```

---

## Task 4: Thread `stop: Stop?` through the survey display path

Pure signature plumbing so the builder receives a `Stop` (for `stop_id`/`route_id`). No new test — verified by build.

**Files:**
- Modify: `OBAKit/Surveys/SurveyDisplayManager.swift:28-58`
- Modify: `OBAKit/Surveys/SurveyBottomSheetController.swift:21-49`
- Modify: `OBAKit/Surveys/SurveyViewController.swift:19-33`
- Modify: `OBAKit/Stops/StopViewController.swift:698-706`

- [ ] **Step 1: Add `stop` to `SurveyViewController`**

In `OBAKit/Surveys/SurveyViewController.swift`, add a stored property after line 20:
```swift
    private let stop: Stop?
```
Update the initializer (line 26) to add the parameter and assignment:
```swift
    init(survey: Survey, surveyService: SurveyService, stop: Stop? = nil, stopID: String? = nil, stopLocation: CLLocationCoordinate2D? = nil, heroResponseID: String? = nil) {
        self.survey = survey
        self.surveyService = surveyService
        self.stop = stop
        self.stopID = stopID
        self.stopLocation = stopLocation
        self.heroResponseID = heroResponseID
        super.init(nibName: nil, bundle: nil)
    }
```

- [ ] **Step 2: Add `stop` to `SurveyBottomSheetController` and forward it**

In `OBAKit/Surveys/SurveyBottomSheetController.swift`, add a stored property after line 19:
```swift
    private let stop: Stop?
```
Update `init` (line 21) to add `stop: Stop? = nil` and `self.stop = stop`, then forward in `setupBottomSheet()` (line 44):
```swift
        let surveyVC = SurveyViewController(
            survey: survey,
            surveyService: surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stopLocation
        )
```

- [ ] **Step 3: Add `stop` to `SurveyDisplayManager` and forward it**

In `OBAKit/Surveys/SurveyDisplayManager.swift`, update `showSurvey` (line 28) to add `stop: Stop? = nil` before `stopID`, and `showBottomSheet` (line 43) to take and forward it:
```swift
    @discardableResult
    public func showSurvey(
        _ survey: Survey,
        in viewController: UIViewController,
        stop: Stop? = nil,
        stopID: String? = nil,
        stopLocation: CLLocationCoordinate2D? = nil,
        presentationStyle: SurveyPresentationStyle = .bottomSheet
    ) -> Bool {
        self.presentingViewController = viewController

        switch presentationStyle {
        case .bottomSheet:
            return showBottomSheet(survey: survey, stop: stop, stopID: stopID, stopLocation: stopLocation)
        }
    }

    private func showBottomSheet(survey: Survey, stop: Stop?, stopID: String?, stopLocation: CLLocationCoordinate2D?) -> Bool {
        guard let presentingViewController = presentingViewController else {
            Logger.warn("Cannot present survey bottom sheet: presentingViewController was deallocated")
            return false
        }

        let bottomSheet = SurveyBottomSheetController(
            survey: survey,
            surveyService: surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stopLocation
        )

        presentingViewController.present(bottomSheet, animated: true)
        return true
    }
```
(`MapViewController.swift:219` calls `showSurvey` without `stop`, so it picks up the `nil` default — no change needed there.)

- [ ] **Step 4: Pass the stop from `StopViewController.showFullSurvey`**

In `OBAKit/Stops/StopViewController.swift` (line ~699):
```swift
    private func showFullSurvey(_ survey: Survey, heroResponseID: String? = nil) {
        let surveyVC = SurveyViewController(
            survey: survey,
            surveyService: application.surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stop?.coordinate,
            heroResponseID: heroResponseID
        )
        let nav = UINavigationController(rootViewController: surveyVC)
        present(nav, animated: true)
    }
```

- [ ] **Step 5: Build for testing to verify it compiles**

Run:
```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Surveys/SurveyDisplayManager.swift OBAKit/Surveys/SurveyBottomSheetController.swift OBAKit/Surveys/SurveyViewController.swift OBAKit/Stops/StopViewController.swift
git commit -m "Thread Stop? through the survey display path (#1148)"
```

---

## Task 5: `ExternalSurveyLauncher` — build, open, and mark-completed-on-success

The testable core of the feature. Lives in OBAKit (uses `UIApplication`); the open call is an injectable seam.

**Files:**
- Create: `OBAKit/Surveys/ExternalSurveyLauncher.swift`
- Test: `OBAKitTests/Surveys/ExternalSurveyLauncherTests.swift` (create)

- [ ] **Step 1: Write the failing tests** (create the test file)

```swift
//
//  ExternalSurveyLauncherTests.swift
//  OBAKitTests
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

@MainActor
final class ExternalSurveyLauncherTests: OBATestCase {

    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var store: UserDefaultsStore!
    nonisolated(unsafe) private var context: MockSurveyURLApplicationContext!
    nonisolated(unsafe) private var service: SurveyService!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).launcher")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
        store = UserDefaultsStore(userDefaults: testUserDefaults)
        store.surveyUserIdentifier = "u-1"
        context = MockSurveyURLApplicationContext()
        service = SurveyService(apiService: nil, userDataStore: store, application: context)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).launcher")
        super.tearDown()
    }

    private func externalSurvey(id: Int = 1, url: String?, fields: [String] = []) -> Survey {
        SurveysTestHelpers.makeSurvey(id: id, questions: [
            SurveysTestHelpers.makeSurveyQuestion(type: .externalSurvey, url: url, embeddedDataFields: fields)
        ])
    }

    private func isCompleted(_ id: Int) -> Bool {
        store.isSurveyCompleted(surveyId: id, userIdentifier: "u-1")
    }

    func test_launch_opensExactURL_marksCompleted_callsOnSuccess() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var opened: URL?
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: { succeeded = true },
                                        onFailure: { failed = true })

        expect(attempted).to(beTrue())
        expect(opened?.absoluteString).to(equal("https://oba.co/s"))
        expect(succeeded).to(beTrue())
        expect(failed).to(beFalse())
        expect(self.isCompleted(1)).to(beTrue())
    }

    func test_launch_appendsStopID_whenStopProvided() {
        let survey = externalSurvey(url: "https://oba.co/s", fields: ["stop_id"])
        let stop = SurveysTestHelpers.makeStop(id: "1_99")
        var opened: URL?
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { url, completion in opened = url; completion(true) }

        launcher.launch(survey: survey, stop: stop, onSuccess: {}, onFailure: {})

        let items = URLComponents(url: opened!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        expect(items.first { $0.name == "stop_id" }?.value).to(equal("1_99"))
    }

    func test_launch_nilURL_doesNotOpen_doesNotComplete_callsOnFailure() {
        let survey = externalSurvey(url: nil)
        var openerCalled = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, _ in openerCalled = true }

        let attempted = launcher.launch(survey: survey, stop: nil,
                                        onSuccess: {},
                                        onFailure: { failed = true })

        expect(attempted).to(beFalse())
        expect(openerCalled).to(beFalse())
        expect(failed).to(beTrue())
        expect(self.isCompleted(1)).to(beFalse())
    }

    func test_launch_openFailure_doesNotComplete_callsOnFailure() {
        let survey = externalSurvey(url: "https://oba.co/s")
        var succeeded = false
        var failed = false
        var launcher = ExternalSurveyLauncher(surveyService: service)
        launcher.urlOpener = { _, completion in completion(false) }

        launcher.launch(survey: survey, stop: nil,
                        onSuccess: { succeeded = true },
                        onFailure: { failed = true })

        expect(succeeded).to(beFalse())
        expect(failed).to(beTrue())
        expect(self.isCompleted(1)).to(beFalse())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/ExternalSurveyLauncherTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: FAIL to compile — `ExternalSurveyLauncher` does not exist.

- [ ] **Step 3: Create `ExternalSurveyLauncher`**

```swift
//
//  ExternalSurveyLauncher.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Builds an external survey's destination URL via `SurveyService` and opens it,
/// marking the survey completed only when the open actually succeeds.
///
/// The open call is an injectable seam so it can be exercised in tests without
/// touching `UIApplication`.
@MainActor
struct ExternalSurveyLauncher {
    let surveyService: SurveyService

    /// Opens `url`, calling back with whether the system handled it.
    var urlOpener: (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }

    /// Builds the survey URL and attempts to open it.
    ///
    /// - Returns: `true` if a URL was built and an open attempted; `false` if no
    ///   openable URL could be produced (in which case `onFailure` is called).
    @discardableResult
    func launch(
        survey: Survey,
        stop: Stop?,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) -> Bool {
        guard let url = surveyService.externalSurveyURL(for: survey, stop: stop) else {
            Logger.error("External survey \(survey.id): no openable URL; not opening.")
            onFailure()
            return false
        }

        urlOpener(url) { success in
            if success {
                surveyService.markSurveyCompleted(survey)
                onSuccess()
            } else {
                Logger.error("External survey \(survey.id): system declined to open \(url).")
                onFailure()
            }
        }
        return true
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/ExternalSurveyLauncherTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: PASS (4 tests). Covers AC 1, 4, 10, 12, 14.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/Surveys/ExternalSurveyLauncher.swift OBAKitTests/Surveys/ExternalSurveyLauncherTests.swift
git commit -m "Add ExternalSurveyLauncher: build + open + mark-completed-on-success (#1148)"
```

---

## Task 6: Render a tappable control in `SurveyViewController` and drive the launcher

**Files:**
- Modify: `OBAKit/Surveys/SurveyViewController.swift:185-189`, plus a lazy launcher and helpers.

- [ ] **Step 1: Add a launcher and the open/error helpers**

In `OBAKit/Surveys/SurveyViewController.swift`, add after the stored properties (after `private var checkboxSelections...`):
```swift
    private lazy var externalSurveyLauncher = ExternalSurveyLauncher(surveyService: surveyService)
```
Add these methods near `showSubmissionError` (anywhere in the class body):
```swift
    private func openExternalSurvey() {
        externalSurveyLauncher.launch(
            survey: survey,
            stop: stop,
            onSuccess: { [weak self] in self?.dismiss(animated: true) },
            onFailure: { [weak self] in self?.showExternalSurveyError() }
        )
    }

    private func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("survey_vc.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("survey_vc.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("survey_vc.ok_button", value: "OK", comment: "OK button on survey alerts"), style: .default))
        present(alert, animated: true)
    }
```

- [ ] **Step 2: Replace the dead `.externalSurvey` row with a label + button**

In `addQuestionRow`, replace the `.externalSurvey` case (lines 185-189):
```swift
        case .externalSurvey:
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
            }

            section <<< ButtonRow(questionTag) { row in
                row.title = OBALoc("survey_vc.open_external_survey_button", value: "Open Survey", comment: "Button that opens an external survey in the browser")
                row.onCellSelection { [weak self] _, _ in
                    self?.openExternalSurvey()
                }
            }
```

- [ ] **Step 3: Build for testing to verify it compiles**

Run:
```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: build succeeds. (Behavior is covered by `ExternalSurveyLauncherTests`; the row is now a tappable `ButtonRow` — AC 13.)

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Surveys/SurveyViewController.swift
git commit -m "SurveyViewController: render tappable external-survey row and open via launcher (#1148)"
```

---

## Task 7: Hero-cell support — `SurveyCell` button, `SurveyStopListItem` closure, `StopViewController` handler

**Files:**
- Modify: `OBAKit/Surveys/SurveyStopListItem.swift:31-51`
- Modify: `OBAKit/Surveys/SurveyCell.swift:94-110`, `:155-179`
- Modify: `OBAKit/Stops/StopViewController.swift:635-656`

- [ ] **Step 1: Add the `onOpenExternalSurvey` closure to `SurveyStopListItem`**

In `OBAKit/Surveys/SurveyStopListItem.swift`, add the property (after `onSelectionChanged`, line 34):
```swift
    let onOpenExternalSurvey: () -> Void
```
Add the parameter to `init` (with a default so other call sites are unaffected) and assign it:
```swift
    init(
        survey: Survey,
        stopID: String?,
        selectedOption: String? = nil,
        onNext: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void,
        onSelectionChanged: @escaping (String?) -> Void,
        onOpenExternalSurvey: @escaping () -> Void = {}
    ) {
        self.survey = survey
        self.stopID = stopID
        self.selectedOption = selectedOption
        self.onNext = onNext
        self.onDismiss = onDismiss
        self.onSelectionChanged = onSelectionChanged
        self.onOpenExternalSurvey = onOpenExternalSurvey
    }
```
Leave the `Equatable`/`Hashable` extensions (lines 56-68) unchanged — they already compare only `survey.id` and `selectedOption`, so the new closure is correctly excluded.

- [ ] **Step 2: Add an "Open Survey" button to `SurveyCell` and show it for `.externalSurvey`**

In `OBAKit/Surveys/SurveyCell.swift`, add a lazy button after `nextButton` (line 92):
```swift
    lazy var externalSurveyButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = OBALoc("survey_cell.open_external_survey_button", value: "Open Survey", comment: "Button that opens an external survey in the browser")
        config.baseBackgroundColor = .systemGreen
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.isHidden = true

        let action = UIAction { [weak self] _ in
            self?.viewModel?.onOpenExternalSurvey()
        }
        button.addAction(action, for: .touchUpInside)
        return button
    }()
```
Add it to `contentStack` (line 101) between `optionsStack` and the spacer:
```swift
    lazy var contentStack: UIStackView = {
        let stack = UIStackView.verticalStack(arrangedSubviews: [
            questionLabel,
            optionsStack,
            externalSurveyButton,
            UIView.spacerView(height: 8.0),
            actionButtonsStack
        ])
        stack.spacing = 8.0
        return stack
    }()
```
In `setupQuestionUI(for:)` (line 155), reset both controls to defaults at the top of the method (right after clearing options, before the `switch`):
```swift
        externalSurveyButton.isHidden = true
        nextButton.isHidden = false
```
Then change the `.label, .externalSurvey` case (line 176) to split them:
```swift
        case .label:
            optionsStack.isHidden = true

        case .externalSurvey:
            optionsStack.isHidden = true
            nextButton.isHidden = true
            externalSurveyButton.isHidden = false
        }
```

- [ ] **Step 3: Wire the hero open handler in `StopViewController`**

In `OBAKit/Stops/StopViewController.swift`, in `surveySection` (line ~643) add the new closure to the `SurveyStopListItem(...)` initializer:
```swift
        let item = SurveyStopListItem(
            survey: survey,
            stopID: stopID,
            onNext: { [weak self] answer in
                self?.handleSurveyAnswer(survey: survey, answer: answer)
            },
            onDismiss: { [weak self] in
                self?.handleSurveyDismiss(survey: survey)
            },
            onSelectionChanged: { _ in },
            onOpenExternalSurvey: { [weak self] in
                self?.handleOpenExternalSurvey(survey: survey)
            }
        )
```
Add the handler near `handleSurveyDismiss` (line ~692):
```swift
    private func handleOpenExternalSurvey(survey: Survey) {
        let launcher = ExternalSurveyLauncher(surveyService: application.surveyService)
        launcher.launch(
            survey: survey,
            stop: stop,
            onSuccess: { [weak self] in self?.listView.applyData() },
            onFailure: { [weak self] in self?.showExternalSurveyError() }
        )
    }

    private func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("stop_controller.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("stop_controller.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("stop_controller.ok_button", value: "OK", comment: "OK button on the external survey error alert"), style: .default))
        present(alert, animated: true)
    }
```

- [ ] **Step 4: Build for testing to verify it compiles**

Run:
```bash
xcodebuild clean build-for-testing -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: build succeeds.

- [ ] **Step 5: Run the full survey test suites to confirm no regressions**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests/ExternalSurveyURLBuilderTests -only-testing:OBAKitTests/SurveyServiceExternalURLTests -only-testing:OBAKitTests/ExternalSurveyLauncherTests -only-testing:OBAKitTests/SurveyServiceStateTests -only-testing:OBAKitTests/SurveyServicePrioritizationTests -only-testing:OBAKitTests/SurveyServiceTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add OBAKit/Surveys/SurveyStopListItem.swift OBAKit/Surveys/SurveyCell.swift OBAKit/Stops/StopViewController.swift
git commit -m "Hero external-survey cell: tappable button wired through to launcher (#1148)"
```

---

## Final verification

- [ ] **Run the complete OBAKitTests suite**

Run:
```bash
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 16'
```
Expected: all tests PASS.

- [ ] **Manual smoke (optional, simulator):** Trigger an external survey on a stop and on the map; confirm the "Open Survey" control appears, tapping opens the URL with the expected query params, the survey is not re-presented after a successful open, and a malformed URL surfaces the error alert without dismissing.

## Out of scope (note in PR description)

`sdk_configuration_values` is not modeled on iOS. External surveys rely on URL + query-param embedded data only. State this explicitly in the PR so it isn't assumed to work.
