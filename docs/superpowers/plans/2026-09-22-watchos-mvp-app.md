# watchOS MVP App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running, independent watchOS app for OneBusAway that shows nearby stops and their arrivals from the watch's own location, with the white-label target structure, opt-in, and CI checks that every later watch step builds on.

**Architecture:** Two new watchOS targets — an `OBAKitWatch` framework (host, models, views) and a thin `WatchApp` shell — opted in per app through `Apps/<App>/watch.yml`. The watch builds no `CoreApplication`: a `WatchAppHost` assembles `LocationService`, `RegionsService`, a standalone `RESTAPIService`, and `Formatters`. Every branch of logic lives in OBAKitCore (five small additions) so the iOS-hosted OBAKitTests suite covers it; OBAKitWatch holds only assembly and SwiftUI.

**Tech Stack:** Swift 6 language mode, SwiftUI + Observation on watchOS 11, XcodeGen 2.46.0 (YAML), Swift Testing, SwiftLint 0.65.1, GitHub Actions (`xcode-27` image), XcodeBuildMCP CLI for simulator driving.

**Spec:** `docs/superpowers/specs/2026-09-22-watchos-mvp-app-design.md` (child of `docs/superpowers/specs/2026-09-20-watchos-architecture-design.md`). Read both before starting a task.

## Global Constraints

- Branch: `watchos/step-4-mvp-app`, stacked on `watchos/step-3-stateless-arrivals`. One PR. Every commit leaves the branch building.
- iOS deployment target stays **18.0**. watchOS deployment target is **11.0**: `deploymentTarget: "11.0"` on the two single-platform watch targets; OBAKitCore already carries `WATCHOS_DEPLOYMENT_TARGET: "11.0"` and is not touched.
- **`Int` is 32 bits on most watches.** Never decode an epoch value into `Int`; use `Int64` or `Date`. The only check that catches this is `xcodebuild build -scheme … -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO`.
- OBAKitCore stays application-extension safe and keeps `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`. OBAKitWatch and WatchApp inherit MainActor-default isolation from `Apps/Shared/app_shared.yml`, which is **not modified**. The five concurrency diagnostic groups are errors.
- The portable `OBAKitCore/` tree gains **no new platform conditionals**. Nothing in this plan touches `OBAKitCoreiOS/`.
- **No `OneBusAway` string literal** in `OBAKitCore/`, `OBAKitWatch/`, or `WatchApp/` (SwiftLint `hardcoded_app_name`, error). App names, bundle IDs, team IDs, and brand assets live under `Apps/OneBusAway/` only.
- Watch code **never reads `\.coreApplication`** (its default value builds a full `CoreApplication`). Watch code never builds a `CoreApplication`, never opens the GRDB stop cache, never writes `UserDataStore`.
- Tests are **Swift Testing** (`@Suite(.serialized)` / `@Test` / `#expect`) in the iOS-hosted `OBAKitTests` target; suites that need fixtures inherit `OBATestCase` and override `init() async throws`. There is no watchOS test target.
- Run `scripts/generate_project OneBusAway` **after adding, moving, or deleting any file** and before every build, or new tests run zero times.
- Resolve simulator UDIDs **in the same shell invocation** that uses them: `SIMULATOR_UDID=$(scripts/resolve_simulator_udid)`; from Task 6 on, `WATCH_UDID=$(scripts/resolve_watch_simulator_udid)`.
- Never pipe `xcodebuild` into `tail`/`grep` without `set -o pipefail`.
- A failing test run can stall up to 10 minutes in `simctl diagnose`; once failures are on screen, kill `xcodebuild`.
- Commit as `aaron@brethorsting.com` (already the worktree's `user.email`). Commit messages carry no attribution lines.
- Use `xcodebuildmcp` (CLI, kebab-case flags) for simulator driving; `touch --down --up` over `tap`.

### Standard commands

Run one suite (substitute the suite name):

```bash
scripts/generate_project OneBusAway && \
SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && \
set -o pipefail && \
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:OBAKitTests/SUITE_NAME 2>&1 | tail -40
```

The whole unit suite: same command with `-only-testing:OBAKitTests`.

Build the watch app for a watch simulator (from Task 6 on):

```bash
scripts/generate_project OneBusAway && \
WATCH_UDID=$(scripts/resolve_watch_simulator_udid) && \
set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme WatchApp \
  -destination "platform=watchOS Simulator,id=$WATCH_UDID" 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | sort -u | tail -40
```

Build every watch target for device architectures (from Task 6 on):

```bash
set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme WatchApp \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u | tail -40
```

## Deviations from the spec, decided while planning

1. **`NearbyStopsLoader` takes `limit` in its initializer**, not per call: `NearbyStopsLoader(limit: 20).stops(near:using:)`. Same behavior; keeps the call site one argument shorter.
2. **`StandaloneAPIServiceProvider` always rebuilds on `updatedRegionsList`**, not only when the base URL changed. `RESTAPIService.init` only builds a URL builder and a decoder, so the check would cost more than the rebuild. The test asserts a new instance after a list update, which the spec's narrower rule also implies.
3. **Localization runs after the views exist** (Task 11), because `genstrings` extracts keys from source. The spec's `WatchApp/<locale>.lproj/InfoPlist.strings` files are created in Task 6 with the project, since they are copies.
4. **Previews exist only for phases constructible without a decoded `Stop`/`ArrivalDeparture`** (Nearby's non-loaded phases and `MessageView`). The `.loaded` phases and the arrivals rows were verified on the simulator with screenshots instead; core has no public fixture builder, and a JSON-decoding preview was judged not worth its weight.

## English strings (single source for Tasks 9–11)

Every watch-only string uses these exact keys and values, through `OBALoc` (Task 9). Task 11 extracts them and translates them.

| Key | English | Comment for translators |
|---|---|---|
| `nearby.title` | Nearby | Screen title before a transit region is known |
| `nearby.refresh` | Refresh | Toolbar button; re-requests location and reloads |
| `nearby.awaiting_authorization` | Allow location access to see stops near you. | Shown while the system location prompt is up |
| `nearby.location_denied` | Location access is off. Nearby stops need your location. | Shown when location is denied or restricted |
| `nearby.locating` | Finding your location… | Progress text |
| `nearby.no_region` | No transit region here. | The fix is outside every supported region |
| `nearby.empty` | No stops nearby. | The server returned zero stops |
| `nearby.retry` | Retry | Button after a failure |
| `arrivals.loading` | Loading departures… | Progress text |
| `arrivals.empty` | No departures in the next 60 minutes. | Empty state |
| `arrivals.no_service` | No transit region selected. | Arrivals cannot load without a region |
| `arrivals.updated_at_fmt` | Updated at %@ | %@ is a short time, e.g. 3:42 PM |
| `arrivals.row.a11y_fmt` | %1$@ to %2$@, %3$@ | VoiceOver: route, headsign, time until departure |

## File Structure

**OBAKitCore additions (Tasks 1–5).** All portable.

| File | Change | Responsibility |
|---|---|---|
| `OBAKitCore/Network/RegionsAPIService.swift` | modify | `standalone(...)` factory |
| `OBAKitCore/Location/Location/LocationManagerProtocol.swift` | modify | `requestLocation()`, `desiredAccuracy` |
| `OBAKitCore/Location/Location/LocationService.swift` | modify | `startsUpdatesOnAuthorization`, async `requestLocation(desiredAccuracy:)`, `LocationServiceError` |
| `OBAKitCore/Network/StandaloneAPIServiceProvider.swift` | create | keeps a standalone `RESTAPIService` on `currentRegion` |
| `OBAKitCore/Network/NearbyStopsLoader.swift` | create | stops near a coordinate, sorted, capped |
| `OBAKitCore/Network/StopArrivalsPoller.swift` | create | periodic arrivals stream for one stop |
| `OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift` | modify | one-shot support |
| `OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift` | modify | one-shot support |
| `OBAKitTests/Helpers/TestClock.swift` | create | manual-advance `Clock` |
| `OBAKitTests/Network/RegionsAPIServiceStandaloneTests.swift` | create | |
| `OBAKitTests/Location/LocationServiceOneShotTests.swift` | create | |
| `OBAKitTests/Network/StandaloneAPIServiceProviderTests.swift` | create | |
| `OBAKitTests/Network/NearbyStopsLoaderTests.swift` | create | |
| `OBAKitTests/Network/StopArrivalsPollerTests.swift` | create | |

**Watch targets and wiring (Tasks 6–7).**

| File | Change | Responsibility |
|---|---|---|
| `OBAKitWatch/project.yml`, `OBAKitWatch/OBAKitWatch.h`, `OBAKitWatch/Info.plist` | create | framework target |
| `OBAKitWatch/WatchRootView.swift` | create (stub) | replaced in Task 9 |
| `WatchApp/project.yml`, `WatchApp/Info.plist`, `WatchApp/WatchApp.swift` | create | app shell |
| `WatchApp/<locale>.lproj/InfoPlist.strings` ×12 | create | location purpose string |
| `Apps/OneBusAway/watch.yml` | create | per-app opt-in |
| `Apps/OneBusAway/WatchAssets.xcassets/` | create | icon + brand color |
| `Apps/OneBusAway/project.yml` | modify | conditional include |
| `Apps/OneBusAway/local.yml.example` | modify | `WatchApp` block |
| `scripts/generate_project` | modify | `--no-watch`, `OBA_WATCH`, identity check, `local.yml` last |
| `scripts/resolve_watch_simulator_udid` | create | |
| `scripts/watch_smoke_test` | create | |
| `scripts/version` | modify | stamp watch plists |
| `fastlane/Fastfile` | modify | `--no-watch` |
| `.swiftlint.yml` | modify | lint the new directories |

**Watch UI (Tasks 8–10).**

| File | Change | Responsibility |
|---|---|---|
| `OBAKitWatch/WatchLocalization.swift` | create | `OBALoc` over the watch bundle |
| `OBAKitWatch/Host/WatchAppHost.swift` | create | assembly |
| `OBAKitWatch/Nearby/NearbyStopsModel.swift` | create | |
| `OBAKitWatch/Nearby/NearbyStopsView.swift` | create | |
| `OBAKitWatch/Nearby/NearbyStopRow.swift` | create | |
| `OBAKitWatch/Shared/MessageView.swift` | create | empty/error states |
| `OBAKitWatch/WatchRootView.swift` | rewrite | navigation, scene phase |
| `OBAKitWatch/Arrivals/StopArrivalsModel.swift` | create | |
| `OBAKitWatch/Arrivals/StopArrivalsView.swift` | create | |
| `OBAKitWatch/Arrivals/ArrivalRow.swift` | create | |

**Localization, CI, docs (Tasks 11–13).**

| File | Change | Responsibility |
|---|---|---|
| `OBAKitWatch/Strings/<locale>.lproj/Localizable.strings` ×13 | create | |
| `scripts/extract_strings` | modify | third block |
| `OBAKitTests/Strings/WatchLocalizationTests.swift` | create | source-tree parity |
| `.github/workflows/tests.yml` | modify | ordering, `WatchApp` compile, smoke test, KiedyBus check |
| `CLAUDE.md`, `README.markdown` | modify | watch commands |

---

## Task 1: `RegionsAPIService.standalone`

**Files:**
- Modify: `OBAKitCore/Network/RegionsAPIService.swift`
- Create: `OBAKitTests/Network/RegionsAPIServiceStandaloneTests.swift`

**Interfaces:**
- Consumes: `APIServiceConfiguration.init(baseURL:apiKey:uuid:appVersion:regionIdentifier:surveyBaseURL:)` (internal), `RegionsAPIService.init(_:dataLoader:)`.
- Produces: `public static func standalone(baseURL: URL, apiKey: String, appVersion: String, uuid: String, dataLoader: URLDataLoader = URLSession.shared) -> RegionsAPIService`. Task 8 calls it.

- [ ] **Step 1: Write the failing test**

```swift
//
//  RegionsAPIServiceStandaloneTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RegionsAPIServiceStandaloneTests: OBATestCase {

    @Test func `Standalone service fetches the regions list through the injected loader`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        let service = RegionsAPIService.standalone(
            baseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )

        let regions = try await service.getRegions(apiPath: regionsAPIPath).list

        #expect(regions.count > 1)
        #expect(regions.contains { $0.name == "Puget Sound" })
    }

    @Test func `Standalone service sends the app identity as query items`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)

        let service = RegionsAPIService.standalone(
            baseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )
        _ = try await service.getRegions(apiPath: regionsAPIPath)

        let url = try #require(dataLoader.recordedRequestURLs.first)
        let query = try #require(url.query)
        #expect(query.contains("key=\(apiKey)"))
        #expect(query.contains("app_uid=\(uuid)"))
        #expect(query.contains("app_ver=\(appVersion)"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the standard single-suite command with `SUITE_NAME=RegionsAPIServiceStandaloneTests`.
Expected: a compile error, `type 'RegionsAPIService' has no member 'standalone'`.

- [ ] **Step 3: Add the factory**

Append to `OBAKitCore/Network/RegionsAPIService.swift`:

```swift

extension RegionsAPIService {
    /// Builds a regions-list service without a `CoreApplication`.
    ///
    /// The watch app's counterpart to `RESTAPIService.standalone`. It exists
    /// because `APIServiceConfiguration`'s initializers are internal, so no
    /// host outside this module can otherwise construct one. Mirrors
    /// `CoreApplication.regionsAPIService` (`regionIdentifier: nil`). The
    /// regions file path is a per-call argument of `getRegions(apiPath:)`, not
    /// part of the configuration.
    public static func standalone(
        baseURL: URL,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) -> RegionsAPIService {
        RegionsAPIService(
            APIServiceConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                uuid: uuid,
                appVersion: appVersion,
                regionIdentifier: nil
            ),
            dataLoader: dataLoader
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: 2 tests passed.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Network/RegionsAPIService.swift OBAKitTests/Network/RegionsAPIServiceStandaloneTests.swift
git commit -m "Add RegionsAPIService.standalone for hosts without a CoreApplication"
```

---

## Task 2: One-shot location in `LocationService`

**Files:**
- Modify: `OBAKitCore/Location/Location/LocationManagerProtocol.swift`
- Modify: `OBAKitCore/Location/Location/LocationService.swift`
- Modify: `OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift`
- Modify: `OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift`
- Create: `OBAKitTests/Location/LocationServiceOneShotTests.swift`

**Interfaces:**
- Consumes: `LocationService.applyAuthorizationState`, `locationManager(_:didUpdateLocations:)`, `locationManager(_:didFailWithError:)` (all in `LocationService.swift`).
- Produces:
  - `LocationManager.requestLocation()`, `LocationManager.desiredAccuracy: CLLocationAccuracy { get set }` — no default implementation.
  - `LocationService.init(userDefaults:locationManager:startsUpdatesOnAuthorization: Bool = true)`.
  - `LocationService.requestLocation(desiredAccuracy: CLLocationAccuracy) async throws -> CLLocation`.
  - `public enum LocationServiceError: Error { case notAuthorized }`.
  - Mocks: `MockAuthorizedLocationManager.requestLocationCount`, `.oneShotLocation: CLLocation?`, `.nextRequestLocationError: Error?`; `LocationManagerMock.requestLocationCount`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  LocationServiceOneShotTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The watch's one-shot location path: `requestLocation(desiredAccuracy:)`
/// and the `startsUpdatesOnAuthorization` opt-out. Continuous-update behavior
/// is covered by `LocationServiceTests`.
@Suite(.serialized)
final class LocationServiceOneShotTests: OBATestCase {

    private func authorizedManager() -> MockAuthorizedLocationManager {
        MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
    }

    @Test func `requestLocation throws before authorization`() async {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        await #expect(throws: LocationServiceError.notAuthorized) {
            _ = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        }
        #expect(manager.requestLocationCount == 0)
    }

    @Test func `requestLocation sets the accuracy and resolves with the manager's fix`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        let fix = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)

        #expect(fix === TestData.mockSeattleLocation)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyHundredMeters)
        #expect(manager.requestLocationCount == 1)
        #expect(service.currentLocation === TestData.mockSeattleLocation)
    }

    @Test func `A worse fix inside the prune window still resolves and still reaches delegates`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        let delegate = LocDelegate()
        service.addDelegate(delegate)

        // Seed an accurate fix, as a cached continuous update would.
        manager.location = TestData.mockSeattleLocation
        #expect(service.currentLocation === TestData.mockSeattleLocation)

        // The one-shot lands seconds later with far worse accuracy — the case
        // the continuous-update prune (successiveLocationComparisonWindow) swallows.
        let coarse = CLLocation(coordinate: TestData.seattleCoordinate, altitude: 100, horizontalAccuracy: 500, verticalAccuracy: 500, timestamp: Date())
        manager.oneShotLocation = coarse

        let fix = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)

        #expect(fix === coarse)
        #expect(service.currentLocation === coarse)
        #expect(delegate.location === coarse)
    }

    @Test func `A manager error fails the request`() async {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        manager.nextRequestLocationError = CLError(.locationUnknown)

        await #expect(throws: CLError.self) {
            _ = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        }
    }

    @Test func `Concurrent callers share one manager request`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        async let first = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        async let second = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        let (a, b) = try await (first, second)

        #expect(a === b)
        // The mock delivers synchronously inside requestLocation(), so the first
        // caller is resolved before the second registers; both must still get a fix.
        #expect(manager.requestLocationCount <= 2)
    }

    @Test func `With startsUpdatesOnAuthorization off, a grant starts neither location nor heading`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        manager.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(manager.locationUpdatesStarted == false)
        #expect(manager.headingUpdatesStarted == false)
    }

    @Test func `With startsUpdatesOnAuthorization off, revocation still stops updates`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        manager.requestWhenInUseAuthorization()

        service.startUpdatingLocation()
        #expect(manager.locationUpdatesStarted)

        manager._authorizationStatus = .denied

        #expect(manager.locationUpdatesStarted == false)
    }

    @Test func `The default still starts updates on a grant`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager)

        manager.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(manager.locationUpdatesStarted)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

`SUITE_NAME=LocationServiceOneShotTests`. Expected: compile errors (`extra argument 'startsUpdatesOnAuthorization'`, `no member 'requestLocation'`).

- [ ] **Step 3: Extend the protocol**

In `OBAKitCore/Location/Location/LocationManagerProtocol.swift`, after the `// MARK: - Location` block's `var location: CLLocation? { get }`, add:

```swift

    // MARK: - One-shot location

    /// Delivers a single fix through `didUpdateLocations`, or an error through
    /// `didFailWithError`. Available on every platform this module builds for;
    /// `CLLocationManager` implements it. No default implementation on purpose:
    /// a mock that forgot it would silently never deliver.
    func requestLocation()

    /// The accuracy the next fix should aim for. `CLLocationManager` implements it.
    var desiredAccuracy: CLLocationAccuracy { get set }
```

`CLLocationManager` already has both members, so its conformance needs nothing.

- [ ] **Step 4: Extend the mocks**

In `OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift`, after `var updatingHeading = false`, add:

```swift
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    /// How many times `requestLocation()` was called.
    private(set) var requestLocationCount = 0

    /// What the next `requestLocation()` delivers instead of `updateLocation`.
    var oneShotLocation: CLLocation?

    /// When set, the next `requestLocation()` delivers this error instead of a
    /// fix, then clears itself.
    var nextRequestLocationError: Error?

    func requestLocation() {
        requestLocationCount += 1
        if let error = nextRequestLocationError {
            nextRequestLocationError = nil
            delegate?.locationManager?(CLLocationManager(), didFailWithError: error)
            return
        }
        location = oneShotLocation ?? updateLocation
    }
```

In `OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift`, in `LocationManagerMock` after `public var headingUpdatesStarted = false`, add:

```swift

    public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    /// How many times `requestLocation()` was called. The base mock is never
    /// authorized, so it records the call and delivers nothing.
    public private(set) var requestLocationCount = 0

    public func requestLocation() {
        requestLocationCount += 1
    }
```

In `AuthorizableLocationManagerMock`, after the `startUpdatingLocation()` override, add:

```swift

    /// One-shot counterpart of `startUpdatingLocation()`: delivers the fix, or
    /// `CLError.denied` with services off, only when authorized.
    public override func requestLocation() {
        super.requestLocation()
        guard authorizationStatus.isAuthorized else { return }

        if simulatesLocationServicesOff {
            delegate?.locationManager?(CLLocationManager(), didFailWithError: CLError(.denied))
        } else {
            location = updateLocation
        }
    }
```

`CountingLocationManagerMock` in `OBAKitTests/ProximityAlerts/ProximityAlertManagerTests.swift` inherits `LocationManagerMock` and needs nothing.

- [ ] **Step 5: Extend `LocationService`**

In `OBAKitCore/Location/Location/LocationService.swift`:

(a) Above the class declaration (after the imports and before the `LocationServiceDelegate` protocol), add:

```swift
/// Errors thrown by `LocationService.requestLocation(desiredAccuracy:)`.
public enum LocationServiceError: Error {
    /// The app is not authorized to use location, so no request was made.
    case notAuthorized
}
```

(b) Replace the two initializers with:

```swift
    public convenience override init() {
        self.init(userDefaults: UserDefaults.standard, locationManager: CLLocationManager())
    }

    /// - parameter startsUpdatesOnAuthorization: When `true` (the iOS default),
    ///   a grant starts continuous location and heading updates immediately —
    ///   Core Location fires the authorization callback the moment the delegate
    ///   is assigned, so an already-authorized app starts its first fix from
    ///   `init`. The watch passes `false`: it takes one-shot fixes through
    ///   ``requestLocation(desiredAccuracy:)`` and never powers the magnetometer.
    ///   Revocation stops updates either way.
    public init(userDefaults: UserDefaults, locationManager: LocationManager, startsUpdatesOnAuthorization: Bool = true) {
        self.locationManager = locationManager
        self.startsUpdatesOnAuthorization = startsUpdatesOnAuthorization
        rawAuthorizationStatus = locationManager.authorizationStatus
        lastAccuracyAuthorization = locationManager.accuracyAuthorization
        currentLocation = locationManager.location

        self.userDefaults = userDefaults

        // Seed the latch from the last session. Location Services being off
        // system-wide survives an app relaunch, but nothing tells us so at
        // launch: the per-app authorization still reads as authorized and no
        // `denied` error has arrived yet. Without this seed the first frames
        // would advertise location as available and then retract it.
        locationServicesDenied = userDefaults.bool(forKey: UserDefaultsKeys.locationServicesDenied)

        super.init()

        registerDefaults()

        self.locationManager.delegate = self
    }

    private let startsUpdatesOnAuthorization: Bool
```

(c) In `applyAuthorizationState`, replace

```swift
        if isLocationUseAuthorized {
            startUpdates()
        } else {
            stopUpdates()
        }
```

with

```swift
        if isLocationUseAuthorized {
            if startsUpdatesOnAuthorization {
                startUpdates()
            }
        } else {
            stopUpdates()
        }
```

(d) After the `// MARK: - Location` section's `stopUpdatingLocation()`, add:

```swift

    // MARK: - One-shot location

    /// Callers suspended in `requestLocation(desiredAccuracy:)`. All resolve on
    /// the next `didUpdateLocations` / `didFailWithError`, whichever comes first.
    private var pendingOneShotRequests: [CheckedContinuation<CLLocation, Error>] = []

    /// Requests a single fix and suspends until the manager delivers one.
    ///
    /// The fix **also becomes `currentLocation`, bypassing the accuracy prune**
    /// that continuous updates apply, so `locationChanged` reaches every
    /// delegate (`RegionsService` selects the region from it). A caller asked
    /// for this fix; a coarser-than-last answer is still the answer. Concurrent
    /// callers share one manager request.
    ///
    /// - throws: ``LocationServiceError/notAuthorized`` when the app may not use
    ///   location, or the manager's error from `didFailWithError`.
    public func requestLocation(desiredAccuracy: CLLocationAccuracy) async throws -> CLLocation {
        guard isLocationUseAuthorized else {
            throw LocationServiceError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingOneShotRequests.append(continuation)
            if pendingOneShotRequests.count == 1 {
                locationManager.desiredAccuracy = desiredAccuracy
                locationManager.requestLocation()
            }
        }
    }

    private func resolveOneShotRequests(with location: CLLocation) {
        let waiters = pendingOneShotRequests
        pendingOneShotRequests.removeAll()
        for waiter in waiters {
            waiter.resume(returning: location)
        }
    }

    private func failOneShotRequests(with error: Error) {
        let waiters = pendingOneShotRequests
        pendingOneShotRequests.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
```

(e) In `locationManager(_:didUpdateLocations:)`, after the `if locationServicesDenied { … }` block and before `guard let currentLocation = currentLocation else {`, add:

```swift
        // A requested fix is delivered as-is: the prune below exists for
        // continuous streams, where a coarse reading trailing a fine one is
        // noise. Here somebody asked for exactly this reading.
        if !pendingOneShotRequests.isEmpty {
            self.currentLocation = newLocation
            resolveOneShotRequests(with: newLocation)
            return
        }
```

(f) In `locationManager(_:didFailWithError:)`, immediately before `notifyDelegatesErrorReceived(error)`, add:

```swift
        failOneShotRequests(with: error)
```

- [ ] **Step 6: Run the new suite and the existing location suites**

`SUITE_NAME=LocationServiceOneShotTests`, then `SUITE_NAME=LocationServiceTests`, then `SUITE_NAME=ProximityAlertManagerTests`. Expected: all pass. If `LocationServiceTests` is named differently, find it with `grep -rl "final class LocationService.*Tests" OBAKitTests`.

- [ ] **Step 7: Build OBAKitCore for watchOS device architectures**

```bash
set -o pipefail && xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u | tail -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add OBAKitCore/Location/Location/LocationManagerProtocol.swift OBAKitCore/Location/Location/LocationService.swift \
  OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift \
  OBAKitTests/Location/LocationServiceOneShotTests.swift
git commit -m "LocationService: async one-shot requestLocation and a startsUpdatesOnAuthorization opt-out"
```

---

## Task 3: `StandaloneAPIServiceProvider`

**Files:**
- Create: `OBAKitCore/Network/StandaloneAPIServiceProvider.swift`
- Create: `OBAKitTests/Network/StandaloneAPIServiceProviderTests.swift`

**Interfaces:**
- Consumes: `RegionsService.currentRegion`, `.addDelegate(_:)`, `RegionsServiceDelegate` (`@objc @MainActor`), `RESTAPIService.standalone(region:apiKey:appVersion:uuid:dataLoader:)`; the `ResolvedRegionPersister` precedent.
- Produces: `@MainActor public final class StandaloneAPIServiceProvider: NSObject, RegionsServiceDelegate` with `public init(regionsService:apiKey:appVersion:uuid:dataLoader:)`, `public private(set) var apiService: RESTAPIService?`, `public var onChange: (() -> Void)?`. Task 8 uses it.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  StandaloneAPIServiceProviderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StandaloneAPIServiceProviderTests: OBATestCase {

    private var locationManager: LocationManagerMock!
    private var locationService: LocationService!
    private var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()
        locationManager = LocationManagerMock()
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManager, startsUpdatesOnAuthorization: false)
        dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
    }

    private func makeRegionsService() -> RegionsService {
        RegionsService(
            apiService: buildRegionsAPIService(dataLoader: dataLoader),
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: regionsAPIPath,
            fileStorage: MockRegionsFileStorage()
        )
    }

    private func makeProvider(_ regionsService: RegionsService) -> StandaloneAPIServiceProvider {
        StandaloneAPIServiceProvider(regionsService: regionsService, apiKey: apiKey, appVersion: appVersion, uuid: uuid, dataLoader: dataLoader)
    }

    @Test func `Seeds from the current region at init`() {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let regionsService = makeRegionsService()
        #expect(regionsService.currentRegion?.name == "Puget Sound")

        let provider = makeProvider(regionsService)

        #expect(provider.apiService != nil)
    }

    @Test func `Is nil with no region`() {
        let regionsService = makeRegionsService()
        #expect(regionsService.currentRegion == nil)

        let provider = makeProvider(regionsService)

        #expect(provider.apiService == nil)
    }

    @Test func `Rebuilds on updatedRegion and calls onChange`() throws {
        let regionsService = makeRegionsService()
        let provider = makeProvider(regionsService)
        var changes = 0
        provider.onChange = { changes += 1 }

        let tampa = try #require(regionsService.regions.first { $0.name == "Tampa Bay" })
        regionsService.currentRegion = tampa

        #expect(provider.apiService != nil)
        #expect(changes == 1)
    }

    @Test func `Rebuilds on updatedRegionsList`() async throws {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let regionsService = makeRegionsService()
        let provider = makeProvider(regionsService)
        let before = try #require(provider.apiService)

        try await regionsService.refreshRegions()

        let after = try #require(provider.apiService)
        #expect(before !== after)
    }

    @Test func `Is retained by nothing but its owner`() {
        let regionsService = makeRegionsService()
        weak var weakProvider: StandaloneAPIServiceProvider?
        do {
            let provider = makeProvider(regionsService)
            weakProvider = provider
            #expect(weakProvider != nil)
        }
        #expect(weakProvider == nil, "RegionsService holds delegates weakly; the host must retain the provider")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

`SUITE_NAME=StandaloneAPIServiceProviderTests`. Expected: compile error, `cannot find 'StandaloneAPIServiceProvider' in scope`.

- [ ] **Step 3: Implement**

```swift
//
//  StandaloneAPIServiceProvider.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Keeps a standalone `RESTAPIService` pointed at `RegionsService.currentRegion`
/// for hosts that build no `CoreApplication` (the watch app).
///
/// It is the region-to-service rule of `CoreApplication.refreshRESTAPIService`
/// with the survey and Obaco branches removed. Seeded from `currentRegion` at
/// init, because the `currentRegion` setter returns early on an unchanged
/// identifier and so delivers no `updatedRegion` on a warm launch. Rebuilt on
/// `updatedRegion` and on `updatedRegionsList` (a server-side edit to the
/// current region arrives only as a list update); nil when there is no region.
///
/// `RegionsService` holds its delegates weakly. The owner retains this object.
@MainActor
public final class StandaloneAPIServiceProvider: NSObject, RegionsServiceDelegate {
    public private(set) var apiService: RESTAPIService?

    /// Called after every rebuild, including one that set `apiService` to nil.
    public var onChange: (() -> Void)?

    private let apiKey: String
    private let appVersion: String
    private let uuid: String
    private let dataLoader: URLDataLoader

    public init(
        regionsService: RegionsService,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) {
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.uuid = uuid
        self.dataLoader = dataLoader
        super.init()

        rebuild(for: regionsService.currentRegion)
        regionsService.addDelegate(self)
    }

    private func rebuild(for region: Region?) {
        if let region {
            apiService = RESTAPIService.standalone(
                region: region,
                apiKey: apiKey,
                appVersion: appVersion,
                uuid: uuid,
                dataLoader: dataLoader
            )
        } else {
            apiService = nil
        }
        onChange?()
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        rebuild(for: region)
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        rebuild(for: service.currentRegion)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command. Expected: 5 passed. If `Rebuilds on updatedRegionsList` fails because `refreshRegions()` does not notify `updatedRegionsList`, read `RegionsService.regions`'s `didSet` and call whichever public path notifies (`updateRegionsList(forceUpdate: true)` is the fallback); do not weaken the assertion.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Network/StandaloneAPIServiceProvider.swift OBAKitTests/Network/StandaloneAPIServiceProviderTests.swift
git commit -m "Add StandaloneAPIServiceProvider: a RESTAPIService that follows currentRegion without a CoreApplication"
```

---

## Task 4: `NearbyStopsLoader`

**Files:**
- Create: `OBAKitCore/Network/NearbyStopsLoader.swift`
- Create: `OBAKitTests/Network/NearbyStopsLoaderTests.swift`

**Interfaces:**
- Consumes: `RESTAPIService.getStops(coordinate:) async throws -> RESTAPIResponse<[Stop]>`; `Stop.location: CLLocation`.
- Produces: `public struct NearbyStopsLoader: Sendable { public init(limit: Int = 20); public func stops(near coordinate: CLLocationCoordinate2D, using apiService: RESTAPIService) async throws -> [Stop] }`. Task 9 uses it.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  NearbyStopsLoaderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyStopsLoaderTests: OBATestCase {

    private let stopsPath = "/api/where/stops-for-location.json"

    /// 15th Ave NE & NE Campus Pkwy, stop 1_10914 in the Seattle fixture.
    private let campusParkway = CLLocationCoordinate2D(latitude: 47.656422, longitude: -122.312164)

    private func mockStops(_ dataLoader: MockDataLoader, fixture: String = "stops_for_location_seattle.json", statusCode: Int = 200) {
        dataLoader.mock(data: Fixtures.loadData(file: fixture), statusCode: statusCode) { [stopsPath] request in
            request.url?.path.contains(stopsPath) ?? false
        }
    }

    @Test func `Stops come back sorted by distance from the coordinate`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)
        let service = buildRESTService(dataLoader: dataLoader)

        let stops = try await NearbyStopsLoader().stops(near: campusParkway, using: service)

        #expect(stops.first?.id == "1_10914")
        let origin = CLLocation(latitude: campusParkway.latitude, longitude: campusParkway.longitude)
        let distances = stops.map { $0.location.distance(from: origin) }
        #expect(distances == distances.sorted())
    }

    @Test func `The list is capped at the limit`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)
        let service = buildRESTService(dataLoader: dataLoader)

        #expect(try await NearbyStopsLoader().stops(near: campusParkway, using: service).count == 20)
        #expect(try await NearbyStopsLoader(limit: 5).stops(near: campusParkway, using: service).count == 5)
    }

    @Test func `An empty response is an empty list`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader, fixture: "stops_for_location_queryfail.json")
        let service = buildRESTService(dataLoader: dataLoader)

        let stops = try await NearbyStopsLoader().stops(near: campusParkway, using: service)

        #expect(stops.isEmpty)
    }

    @Test func `A server error propagates`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader, statusCode: 500)
        let service = buildRESTService(dataLoader: dataLoader)

        await #expect(throws: (any Error).self) {
            _ = try await NearbyStopsLoader().stops(near: campusParkway, using: service)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

`SUITE_NAME=NearbyStopsLoaderTests`. Expected: `cannot find 'NearbyStopsLoader' in scope`.

- [ ] **Step 3: Implement**

```swift
//
//  NearbyStopsLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Stops near a coordinate, nearest first, capped. Stateless; the watch's
/// Nearby screen calls it once per location fix.
///
/// `getStops(coordinate:)` has no radius parameter — the server applies its
/// default — so the cap is client-side over whatever the server returned.
public struct NearbyStopsLoader: Sendable {
    public let limit: Int

    public init(limit: Int = 20) {
        self.limit = limit
    }

    public func stops(near coordinate: CLLocationCoordinate2D, using apiService: RESTAPIService) async throws -> [Stop] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let stops = try await apiService.getStops(coordinate: coordinate).list

        return Array(
            stops
                .sorted { $0.location.distance(from: origin) < $1.location.distance(from: origin) }
                .prefix(limit)
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Same command. Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Network/NearbyStopsLoader.swift OBAKitTests/Network/NearbyStopsLoaderTests.swift
git commit -m "Add NearbyStopsLoader: stops near a coordinate, nearest first, capped"
```

---

## Task 5: `TestClock` and `StopArrivalsPoller`

**Files:**
- Create: `OBAKitTests/Helpers/TestClock.swift`
- Create: `OBAKitCore/Network/StopArrivalsPoller.swift`
- Create: `OBAKitTests/Network/StopArrivalsPollerTests.swift`

**Interfaces:**
- Consumes: `BookmarkArrivalsLoader(minutesAfter:).arrivals(for:using:)`, `BookmarkArrivalsRequest(stopID:).matching(_:)`, `SendableBox` (`OBAKitTests/Helpers/SendableBox.swift` — read it; if its API differs from the `value` get/set used below, adapt the test, not the poller), `poll(until:)` (`OBAKitTests/Helpers/Polling.swift`).
- Produces: `public struct StopArrivalsPoller: Sendable { public init(minutesAfter: UInt = 60); public func arrivals(for stopID: StopID, every interval: Duration, using apiService: RESTAPIService, clock: some Clock<Duration>) -> AsyncStream<Result<[ArrivalDeparture], Error>> }`; `final class TestClock: Clock` with `advance(by:)` and `sleeperCount`. Task 10 uses the poller.

- [ ] **Step 1: Write `TestClock`**

```swift
//
//  TestClock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A `Clock` that only moves when a test calls `advance(by:)`.
///
/// `sleep(until:)` parks the caller until the clock reaches the deadline;
/// cancellation throws `CancellationError` and unparks only the cancelled
/// caller. Tests wait for `sleeperCount` to reach the expected value before
/// advancing, so the sleeper is registered before the clock moves.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    typealias Duration = Swift.Duration

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentInstant = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []

    var now: Instant {
        lock.withLock { currentInstant }
    }

    var minimumResolution: Duration { .zero }

    /// How many callers are parked in `sleep`.
    var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id = UUID()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let dueNow = lock.withLock { () -> Bool in
                    if deadline <= currentInstant {
                        return true
                    }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if dueNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock forward and wakes every sleeper whose deadline has passed.
    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            currentInstant = currentInstant.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= currentInstant }
            sleepers.removeAll { $0.deadline <= currentInstant }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}
```

- [ ] **Step 2: Write the failing poller tests**

```swift
//
//  StopArrivalsPollerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopArrivalsPollerTests: OBATestCase {

    private let stopID = "1_75414"
    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    /// Thread-safe request counter and failure switch; matchers run off-main.
    private nonisolated final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        private var _failing = false

        var requests: Int { lock.withLock { _requests } }
        var failing: Bool {
            get { lock.withLock { _failing } }
            set { lock.withLock { _failing = newValue } }
        }
        func record() { lock.withLock { _requests += 1 } }
    }

    private func mockArrivals(_ dataLoader: MockDataLoader, gate: Gate) {
        // Order matters: MockDataLoader returns the first matcher that accepts.
        dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true, gate.failing else { return false }
            gate.record()
            return true
        }
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard request.url?.path.contains(arrivalsPath) == true else { return false }
            gate.record()
            return true
        }
    }

    @Test func `Emits once immediately`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        let first = try #require(await iterator.next())
        let arrivals = try first.get()
        // The fixture's departures are from 2018, so `matching` (which drops
        // `.past`) leaves nothing — proving the filter runs. That the fetch
        // happened is the request count; non-empty delivery is covered by
        // BookmarkArrivalsLoaderTests and the widget tests.
        #expect(arrivals.isEmpty)
        #expect(gate.requests == 1)
    }

    @Test func `Emits again on each tick`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await poll(until: clock.sleeperCount == 1, "the poller should be sleeping until the next tick")
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        #expect((try? second.get()) != nil)
        #expect(gate.requests == 2)
    }

    @Test func `A failed tick delivers a failure and the next tick recovers`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        gate.failing = true
        let stream = StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock)
        var iterator = stream.makeAsyncIterator()

        let first = try #require(await iterator.next())
        guard case .failure = first else {
            Issue.record("expected the first tick to fail")
            return
        }

        gate.failing = false
        await poll(until: clock.sleeperCount == 1, "the poller should survive a failure and sleep")
        clock.advance(by: .seconds(30))

        let second = try #require(await iterator.next())
        guard case .success = second else {
            Issue.record("expected the second tick to succeed")
            return
        }
        #expect(gate.requests == 2)
    }

    @Test func `Cancelling the consumer stops the fetches`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let gate = Gate()
        mockArrivals(dataLoader, gate: gate)
        let service = buildRESTService(dataLoader: dataLoader)
        let clock = TestClock()

        let consumer = Task {
            for await _ in StopArrivalsPoller().arrivals(for: stopID, every: .seconds(30), using: service, clock: clock) {
                // consume forever
            }
        }
        await poll(until: gate.requests == 1)
        await poll(until: clock.sleeperCount == 1)

        consumer.cancel()
        _ = await consumer.value

        await poll(until: clock.sleeperCount == 0, "cancellation should unpark the sleeper")
        clock.advance(by: .seconds(60))
        try await Task.sleep(for: .milliseconds(50))
        #expect(gate.requests == 1)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

`SUITE_NAME=StopArrivalsPollerTests`. Expected: `cannot find 'StopArrivalsPoller' in scope`.

- [ ] **Step 4: Implement the poller**

```swift
//
//  StopArrivalsPoller.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Upcoming departures for one stop, refetched on a fixed cadence for as long
/// as the consumer keeps reading. The watch's stop screen runs one while the
/// scene is active and cancels it when the scene leaves the foreground.
///
/// A fetch failure is delivered as a `.failure` value, never thrown, so one
/// bad tick does not end the stream — the same convention as
/// `BookmarkArrivalsLoader`, which does the fetching. The consumer keeps its
/// last good value.
public struct StopArrivalsPoller: Sendable {
    private let minutesAfter: UInt

    public init(minutesAfter: UInt = 60) {
        self.minutesAfter = minutesAfter
    }

    /// Emits immediately, then after every `interval` measured on `clock`,
    /// until the consumer stops iterating.
    public func arrivals(
        for stopID: StopID,
        every interval: Duration,
        using apiService: RESTAPIService,
        clock: some Clock<Duration>
    ) -> AsyncStream<Result<[ArrivalDeparture], Error>> {
        let loader = BookmarkArrivalsLoader(minutesAfter: minutesAfter)
        let request = BookmarkArrivalsRequest(stopID: stopID)

        let (stream, continuation) = AsyncStream<Result<[ArrivalDeparture], Error>>.makeStream()

        let task = Task {
            while !Task.isCancelled {
                for await (_, result) in loader.arrivals(for: [request], using: apiService) {
                    continuation.yield(result.map { request.matching($0) })
                }

                do {
                    try await clock.sleep(for: interval)
                } catch {
                    break
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }

        return stream
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Same command. Expected: 4 passed. If `clock.sleep(for:)` does not resolve on `some Clock<Duration>`, use `try await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)` instead.

- [ ] **Step 6: Build OBAKitCore for watchOS device architectures** (command in Task 2, Step 7). Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add OBAKitTests/Helpers/TestClock.swift OBAKitCore/Network/StopArrivalsPoller.swift OBAKitTests/Network/StopArrivalsPollerTests.swift
git commit -m "Add StopArrivalsPoller: a cadence-driven arrivals stream for one stop, with a TestClock"
```

---

## Task 6: Watch targets, opt-in, and project scripts

**Files:**
- Create: `OBAKitWatch/project.yml`, `OBAKitWatch/OBAKitWatch.h`, `OBAKitWatch/Info.plist`, `OBAKitWatch/WatchRootView.swift` (stub)
- Create: `WatchApp/project.yml`, `WatchApp/Info.plist`, `WatchApp/WatchApp.swift`, `WatchApp/<locale>.lproj/InfoPlist.strings` ×12
- Create: `Apps/OneBusAway/watch.yml`, `Apps/OneBusAway/WatchAssets.xcassets/**`
- Modify: `Apps/OneBusAway/project.yml`, `Apps/OneBusAway/local.yml.example`, `scripts/generate_project`, `scripts/version`, `fastlane/Fastfile`, `.swiftlint.yml`
- Create: `scripts/resolve_watch_simulator_udid`

**Interfaces:**
- Produces: targets `OBAKitWatch` and `WatchApp` (schemes of the same names); `scripts/generate_project [APP] [--no-watch]`; `OBA_WATCH` env; `scripts/resolve_watch_simulator_udid`. Everything after this task depends on them.

- [ ] **Step 1: Record the KiedyBus baseline before touching anything**

```bash
scripts/generate_project KiedyBus >/dev/null && \
cp OBAKit.xcodeproj/project.pbxproj "$SCRATCH/kiedybus-before.pbxproj" && \
git checkout -- Apps OBAKit OBAKitCore OBAWidget 2>/dev/null; git status --short
```

where `$SCRATCH` is the session scratchpad directory. (`scripts/version` stamps `CFBundleVersion` into tracked plists; the `git checkout --` reverts that.) Expected: clean status.

- [ ] **Step 2: Create the framework target**

`OBAKitWatch/project.yml`:

```yaml
targets:
  OBAKitWatch:
    type: framework
    platform: watchOS
    deploymentTarget: "11.0"
    sources:
      # XcodeGen's synced folders can't mark headers public, so the umbrella
      # header is carved out of the buildable folder and added as an explicit
      # public header. project.yml is excluded so it does not ship as a resource.
      - path: "."
        excludes: ["OBAKitWatch.h", "project.yml"]
      - path: OBAKitWatch.h
        headerVisibility: public
    dependencies:
      - target: OBAKitCore
    # A declared scheme so `xcodebuild -scheme OBAKitWatch` exists on a fresh
    # checkout; XcodeGen writes shared schemes only for targets that ask.
    scheme:
      gatherCoverageData: false
    postBuildScripts:
      - path: "../scripts/swiftlint.sh"
        name: Swiftlint
        basedOnDependencyAnalysis: false
    info:
      path: "Info.plist"
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
    settings:
      base:
        # The step 6 watch widget extension links this framework.
        APPLICATION_EXTENSION_API_ONLY: true
        # Swift language mode, checking level, and MainActor default isolation
        # come from the project-wide base in Apps/Shared/app_shared.yml.
```

`OBAKitWatch/OBAKitWatch.h`:

```objc
//
//  OBAKitWatch.h
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>

//! Project version number for OBAKitWatch.
FOUNDATION_EXPORT double OBAKitWatchVersionNumber;

//! Project version string for OBAKitWatch.
FOUNDATION_EXPORT const unsigned char OBAKitWatchVersionString[];
```

`OBAKitWatch/Info.plist`: generated by XcodeGen from the `info:` block above on the first `scripts/generate_project` run (Step 8); commit it as generated. (superseded: gitignored during the simplify pass)

`OBAKitWatch/WatchRootView.swift` (stub, replaced in Task 9):

```swift
//
//  WatchRootView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The watch app's root. Replaced with the real navigation in Task 9.
public struct WatchRootView: View {
    public init() {}

    public var body: some View {
        Text("Nearby")
    }
}
```

- [ ] **Step 3: Create the app target**

`WatchApp/project.yml`:

```yaml
targets:
  WatchApp:
    type: application
    platform: watchOS
    deploymentTarget: "11.0"
    sources:
      - path: "."
        excludes: ["project.yml"]
    dependencies:
      - target: OBAKitWatch
      - target: OBAKitCore
    scheme:
      gatherCoverageData: false
    info:
      path: Info.plist
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleLocalizations:
          - ar
          - en
          - es
          - fil
          - fr
          - it
          - ko
          - pl
          - pt-BR
          - ru
          - vi
          - zh-Hans
          - zh-Hant
        WKApplication: true
        WKRunsIndependentlyOfCompanionApp: true
        # App-neutral: the system prefixes the app name. Translations live in
        # <locale>.lproj/InfoPlist.strings beside this file.
        NSLocationWhenInUseUsageDescription: See where you are in relation to transit, and help you navigate more easily.
    settings:
      base:
        # XcodeGen's watchOS application preset omits this; without it the app
        # installs and dies in dyld ("Library not loaded: @rpath/OBAKitWatch").
        # A compile cannot catch it — scripts/watch_smoke_test does.
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

`WatchApp/Info.plist` and `OBAKitWatch/Info.plist`: **do not hand-write them.** XcodeGen writes each file at its target's `info.path` from the `info.properties` block on every generation (that is how `OBAWidget/Info.plist` is maintained), so after Step 8's first `scripts/generate_project OneBusAway` the two files exist; commit them as generated. (superseded: gitignored during the simplify pass) Per-app keys that `watch.yml` adds (`CFBundleDisplayName`, `OBAKitConfig`) land in the generated `WatchApp/Info.plist` exactly as they do in `OBAWidget/Info.plist` today. `scripts/version` stamps `CFBundleVersion` into the checked-in copies.

`WatchApp/WatchApp.swift`:

```swift
//
//  WatchApp.swift
//  WatchApp
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitWatch

/// The thin, white-label shell. Everything with a branch in it lives in
/// OBAKitWatch (views, host) or OBAKitCore (logic); an app opts in through its
/// `Apps/<App>/watch.yml`.
@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
```

`WatchApp/<locale>.lproj/InfoPlist.strings` for the 12 non-English locales: one line each, copied from the app's translations:

```bash
for d in Apps/OneBusAway/*.lproj; do
  loc=$(basename "$d" .lproj); [ "$loc" = "Base" ] && continue
  mkdir -p "WatchApp/$loc.lproj"
  grep '^"NSLocationWhenInUseUsageDescription"' "$d/InfoPlist.strings" > "WatchApp/$loc.lproj/InfoPlist.strings"
done
ls WatchApp/*.lproj | head; wc -l WatchApp/*/InfoPlist.strings
```

Expected: 12 directories, each file exactly 1 line.

- [ ] **Step 4: Create the per-app opt-in**

`Apps/OneBusAway/watch.yml`:

```yaml
############
# OneBusAway watch app
############
#
# Every line of watch wiring for this app. Included from project.yml only when
# OBA_WATCH is set (scripts/generate_project sets it unless given --no-watch).
# An app with no watch.yml generates exactly the project it generates today.

# This file is included with `relativePaths: false`, so these paths resolve
# from the repo root. The nested includes keep the default (paths inside
# OBAKitWatch/project.yml resolve from OBAKitWatch/, as OBAKitCore's do).
include:
  - path: OBAKitWatch/project.yml
  - path: WatchApp/project.yml

targets:
  App:
    dependencies:
      - target: WatchApp
  WatchApp:
    sources:
      - path: Apps/OneBusAway/Resources/regions.json
      - path: Apps/OneBusAway/WatchAssets.xcassets
    entitlements:
      path: Apps/OneBusAway/WatchApp.entitlements
      properties:
        com.apple.security.application-groups:
          - group.org.onebusaway.iphone
    info:
      properties:
        CFBundleDisplayName: OneBusAway
        WKCompanionAppBundleIdentifier: org.onebusaway.iphone
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: false
          NSExceptionDomains: {
            "onebusaway.co": {
                NSIncludesSubdomains: true,
                NSExceptionAllowsInsecureHTTPLoads: true
            },
            "sidecar.onebusaway.org": {
                NSIncludesSubdomains: true,
                NSExceptionAllowsInsecureHTTPLoads: true
            }
          }
        OBAKitConfig:
          AppGroup: group.org.onebusaway.iphone
          BundledRegionsFileName: regions.json
          RESTServerAPIKey: org.onebusaway.iphone
          RegionsServerBaseAddress: https://regions.onebusaway.org
          RegionsServerAPIPath: /regions-v3.json
    settings:
      base:
        DEVELOPMENT_TEAM: 4ZQCMA634J
        PRODUCT_BUNDLE_IDENTIFIER: org.onebusaway.iphone.watchkitapp
```

`Apps/OneBusAway/WatchAssets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Apps/OneBusAway/WatchAssets.xcassets/AppIcon.appiconset/Contents.json` (copy `big.png` from `Apps/OneBusAway/Assets.xcassets/AppIcon.appiconset/` into this directory):

```json
{
  "images" : [
    {
      "filename" : "big.png",
      "idiom" : "universal",
      "platform" : "watchos",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Apps/OneBusAway/WatchAssets.xcassets/brand.colorset/Contents.json`: copy `Apps/OneBusAway/Assets.xcassets/Colors/brand.colorset/Contents.json` verbatim.

In `Apps/OneBusAway/project.yml`, append to the **existing** `include:` list (last entry):

```yaml
  - path: Apps/OneBusAway/watch.yml
    relativePaths: false
    enable: ${OBA_WATCH}
```

In `Apps/OneBusAway/local.yml.example`, append:

```yaml
  # Only used when the watch app is generated (the default; see
  # scripts/generate_project --no-watch).
  WatchApp:
    settings:
      base:
        DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

- [ ] **Step 5: Teach `scripts/generate_project` the flag, the env var, the identity check, and last-include `local.yml`**

Replace the top of the script (everything before `BEGIN {`) with:

```ruby
#!/usr/bin/env ruby

require "yaml"
require "json"

args = ARGV.dup
no_watch = args.delete("--no-watch")
app = args.shift

if app.nil?
  display_usage_information
  puts ""
  puts "Defaulting to OneBusAway."
  app = "OneBusAway"
  puts ""
end

check_for_project_file(app)

# An unset variable disables the `enable: ${OBA_WATCH}` include in an app's
# project.yml; any value enables it. Apps without a watch.yml are unaffected.
# --no-watch must also clear a value inherited from the caller's environment.
if no_watch
  ENV.delete("OBA_WATCH")
else
  ENV["OBA_WATCH"] = "true"
end

generate_project(app)
check_watch_identity(app) unless no_watch

puts `scripts/version`
```

In `display_usage_information`, change the usage line to `puts "Usage: scripts/generate_project <APP NAME> [--no-watch]"` and add `puts "  --no-watch   skip the watch targets (faster iOS-only builds; no watchOS platform needed)"` after the apps list.

Replace `splice_include` so `local.yml` is the **last** include (a later include wins over an earlier one, and `watch.yml` sets `WatchApp`'s team):

```ruby
  def splice_include(project, local)
    include = project.index(/^include:\s*$/)
    abort "Could not find include list in project.yml." unless include

    # Find the end of the include list: the first line after `include:` that is
    # not an indented list item or a blank line.
    cursor = project.index("\n", include) + 1
    while cursor < project.length
      line_end = project.index("\n", cursor) || project.length
      line = project[cursor...line_end]
      break unless line.empty? || line.start_with?("  ")
      cursor = line_end + 1
    end
    project.insert([cursor, project.length].min, "  - path: #{local}\n")
  end
```

In `replace_development_team`, replace the `abort "Could not find target …"` line with `return project unless target_start` and add a comment: `# Targets that only exist in an included file (WatchApp, in watch.yml) are handled by local.yml being the last include.`

Add the identity check inside the `BEGIN` block:

```ruby
  # Simulator builds accept a wrong companion ID and an unprefixed watch bundle
  # ID; the mistake surfaces only at device install or App Store validation.
  # Read the resolved spec and refuse to hand back a project that would.
  def check_watch_identity(app)
    dump = `xcodegen dump --type json 2>/dev/null`
    abort "xcodegen dump failed; cannot verify the watch app's identity." unless $?.success?

    targets = JSON.parse(dump).fetch("targets", {})
    watch = targets["WatchApp"]
    return unless watch # this app has no watch.yml

    app_id = targets.dig("App", "settings", "base", "PRODUCT_BUNDLE_IDENTIFIER")
    watch_id = watch.dig("settings", "base", "PRODUCT_BUNDLE_IDENTIFIER")
    companion = watch.dig("info", "properties", "WKCompanionAppBundleIdentifier")

    abort "#{app}: WatchApp needs PRODUCT_BUNDLE_IDENTIFIER in its watch.yml override." unless watch_id
    abort "#{app}: WKCompanionAppBundleIdentifier (#{companion.inspect}) must equal the App bundle ID (#{app_id})." unless companion == app_id
    abort "#{app}: the watch bundle ID (#{watch_id}) must be prefixed by the App bundle ID (#{app_id}.)." unless watch_id.start_with?("#{app_id}.")
  end
```

- [ ] **Step 6: Stamp the watch plists, guard the release lane, lint the new directories**

`scripts/version`: change `apps += ["OBAKit", "OBAKitCore", "OBAWidget"]` to `apps += ["OBAKit", "OBAKitCore", "OBAWidget", "OBAKitWatch", "WatchApp"]`.

`fastlane/Fastfile`: change `sh("scripts/generate_project", "OneBusAway")` to:

```ruby
      # --no-watch until the watch app has a hardware pass and App Store Connect
      # identifiers (see docs/superpowers/specs/2026-09-22-watchos-mvp-app-design.md,
      # Decisions). Without it every TestFlight build would embed the watch app.
      sh("scripts/generate_project", "OneBusAway", "--no-watch")
```

`.swiftlint.yml`: add `  - OBAKitWatch` and `  - WatchApp` to `included:`, and extend the `hardcoded_app_name` comment's first line to `# OBAKit/OBAKitCore/OBAKitCoreiOS/OBAWidget/OBAKitWatch/WatchApp are the white-label frameworks and shells — the same code ships`.

- [ ] **Step 7: Write `scripts/resolve_watch_simulator_udid`**

```bash
#!/usr/bin/env bash
#
# Prints the UDID of the first available Apple Watch simulator on the newest
# installed watchOS runtime, creating one from the newest Apple Watch device
# type if none exists. Mirrors scripts/resolve_simulator_udid: address devices
# by id=, never by a name that goes stale every Xcode release.
#
# Usage:
#   WATCH_UDID=$(scripts/resolve_watch_simulator_udid)
#   xcodebuild ... -destination "platform=watchOS Simulator,id=$WATCH_UDID"

set -euo pipefail

if ! devices_json=$(xcrun simctl list devices available -j 2>&1); then
    echo "error: \`xcrun simctl\` failed:" >&2
    echo "$devices_json" >&2
    exit 1
fi

udid=$(printf '%s' "$devices_json" | python3 -c '
import json, re, sys

try:
    devices = json.load(sys.stdin)["devices"]
except (json.JSONDecodeError, KeyError, TypeError) as error:
    sys.exit("error: could not parse the device list: " + str(error))

def version(runtime):
    match = re.search(r"watchOS-(\d+)-(\d+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)

for runtime in sorted(devices, key=version, reverse=True):
    if not re.search(r"watchOS-\d+-\d+", runtime):
        continue
    watches = [d for d in devices[runtime] if "Apple-Watch" in d.get("deviceTypeIdentifier", "")]
    if watches:
        print(watches[0]["udid"])
        break
')

if [ -z "$udid" ]; then
    # No device on any watchOS runtime: create one from the newest runtime and
    # the first Apple Watch device type it supports.
    runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, re, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "watchOS" and r["isAvailable"]]
if not runtimes:
    sys.exit("error: no watchOS runtime is installed. Run: xcodebuild -downloadPlatform watchOS")
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
print(runtimes[0]["identifier"])
')
    devicetype=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = [t for t in json.load(sys.stdin)["devicetypes"] if t["name"].startswith("Apple Watch")]
if not types:
    sys.exit("error: no Apple Watch device types are installed.")
print(types[0]["identifier"])
')
    udid=$(xcrun simctl create "OBA Watch Smoke" "$devicetype" "$runtime")
fi

printf '%s\n' "$udid"
```

`chmod +x scripts/resolve_watch_simulator_udid`.

- [ ] **Step 8: Generate and build everything**

```bash
scripts/generate_project OneBusAway && \
xcodebuild -list -project OBAKit.xcodeproj | sed -n '/Targets:/,/Schemes:/p'
```

Expected: `OBAKitWatch` and `WatchApp` listed among targets; the identity check printed nothing and exited 0.

Then the "Build the watch app for a watch simulator" standard command. Expected: `BUILD SUCCEEDED`. If it reports a duplicate `Info.plist` or asset-catalog error, read the error and fix the YAML; do not remove `LD_RUNPATH_SEARCH_PATHS`.

Then the iOS app:

```bash
SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u | tail -20
```

Expected: `BUILD SUCCEEDED`, and `find ~/Library/Developer/Xcode/DerivedData -path "*App.app/Watch/WatchApp.app" | head -1` finds the embedded watch app (search the `-derivedDataPath` if one was given).

Then device architectures: the "Build every watch target for device architectures" standard command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Prove the opt-out and the KiedyBus invariant**

```bash
scripts/generate_project OneBusAway --no-watch >/dev/null && \
xcodebuild -list -project OBAKit.xcodeproj | grep -c "WatchApp" ; \
scripts/generate_project KiedyBus >/dev/null && \
diff <(grep -v "CFBundleVersion" "$SCRATCH/kiedybus-before.pbxproj") <(grep -v "CFBundleVersion" OBAKit.xcodeproj/project.pbxproj) && echo "KiedyBus unchanged"; \
git checkout -- Apps OBAKit OBAKitCore OBAWidget OBAKitWatch WatchApp 2>/dev/null
```

Expected: `0`, then `KiedyBus unchanged`. (A pbxproj diff that is only object-ID churn means XcodeGen reordered something: investigate, do not accept.)

Then a negative identity probe: temporarily change `WKCompanionAppBundleIdentifier` in `watch.yml` to `org.example.wrong`, run `scripts/generate_project OneBusAway`, expect a non-zero exit with the companion message, and revert.

- [ ] **Step 10: Regenerate for OneBusAway, lint, and commit**

```bash
scripts/generate_project OneBusAway >/dev/null && scripts/swiftlint.sh | tail -5
git add OBAKitWatch WatchApp Apps/OneBusAway/watch.yml Apps/OneBusAway/WatchAssets.xcassets Apps/OneBusAway/project.yml \
  Apps/OneBusAway/local.yml.example scripts/generate_project scripts/resolve_watch_simulator_udid scripts/version \
  fastlane/Fastfile .swiftlint.yml
git status --short
git commit -m "Add the OBAKitWatch framework and WatchApp shell, opted in per app through watch.yml"
```

If `git status` shows stamped `Info.plist` changes under `Apps/`, `OBAKit/`, `OBAKitCore/`, or `OBAWidget/`, revert those with `git checkout --` before committing; the new `OBAKitWatch/Info.plist` and `WatchApp/Info.plist` are committed as generated. (superseded: gitignored during the simplify pass)

---

## Task 7: Launch smoke test

**Files:**
- Create: `scripts/watch_smoke_test`

**Interfaces:**
- Consumes: `scripts/resolve_watch_simulator_udid`, the `WatchApp` scheme.
- Produces: `scripts/watch_smoke_test [DERIVED_DATA_PATH]` exiting 0 on a live app and 1 otherwise. Task 12's CI step runs it.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
#
# Builds WatchApp for an unpaired watch simulator, installs it, launches it,
# and asserts it is still alive 8 seconds later.
#
# Why this exists: `simctl launch` (and XcodeBuildMCP's build_run_sim) print a
# PID and exit 0 even when dyld kills the app 10 ms later — which is exactly
# what a missing LD_RUNPATH_SEARCH_PATHS does. A compile cannot catch dyld,
# Info.plist, or embedding failures; this can.
#
# Usage: scripts/watch_smoke_test [DERIVED_DATA_PATH]
#   Assumes OBAKit.xcodeproj was generated with the watch targets enabled.

set -euo pipefail

derived=${1:-DerivedData}
[[ $derived = /* ]] || derived="$PWD/$derived"
cd "$(dirname "$0")/.."

udid=$(scripts/resolve_watch_simulator_udid)

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

# `-quiet` prints only warnings and errors; `set -e` fails the script on a
# failed build, so a broken compile is reported as itself, not as a missing app.
xcodebuild build \
  -project OBAKit.xcodeproj \
  -scheme WatchApp \
  -destination "platform=watchOS Simulator,id=$udid" \
  -derivedDataPath "$derived" \
  -quiet

app=$(find "$derived/Build/Products" -type d -name "WatchApp.app" -path "*watchsimulator*" | head -1)
if [ -z "$app" ]; then
    echo "error: WatchApp.app not found under $derived/Build/Products" >&2
    exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")

xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
xcrun simctl install "$udid" "$app"
launch_output=$(xcrun simctl launch "$udid" "$bundle_id")
pid=${launch_output##*: }
echo "launched $bundle_id as pid $pid; waiting 8 s"
sleep 8

alive=0
if kill -0 "$pid" 2>/dev/null; then
    alive=1
fi
registered=0
if xcrun simctl spawn "$udid" launchctl list 2>/dev/null | grep -q "$bundle_id"; then
    registered=1
fi

if [ "$alive" = 1 ] && [ "$registered" = 1 ]; then
    echo "PASS: $bundle_id is running (pid $pid) and registered with launchd"
    exit 0
fi

echo "FAIL: alive=$alive registered=$registered" >&2
echo "--- last minute of simulator log mentioning the app or dyld ---" >&2
xcrun simctl spawn "$udid" log show --last 2m \
  --predicate "eventMessage CONTAINS 'Library not loaded' OR process == 'WatchApp' OR eventMessage CONTAINS '$bundle_id'" 2>/dev/null | tail -60 >&2 || true
exit 1
```

`chmod +x scripts/watch_smoke_test`.

- [ ] **Step 2: Run it against the good build**

```bash
scripts/generate_project OneBusAway >/dev/null && scripts/watch_smoke_test "$SCRATCH/dd"
```

Expected: `PASS: org.onebusaway.iphone.watchkitapp is running …`, exit 0.

- [ ] **Step 3: Negative probe**

Comment out the `LD_RUNPATH_SEARCH_PATHS` line in `WatchApp/project.yml`, regenerate, run the smoke test. Expected: `FAIL`, exit 1, and the log excerpt mentions `Library not loaded`. Restore the line, regenerate, run again: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add scripts/watch_smoke_test
git commit -m "Add scripts/watch_smoke_test: install, launch, and assert the watch app stays alive"
```

---

## Task 8: `OBALoc` and `WatchAppHost`

**Files:**
- Create: `OBAKitWatch/WatchLocalization.swift`
- Create: `OBAKitWatch/Host/WatchAppHost.swift`

**Interfaces:**
- Consumes: `LocationService(userDefaults:locationManager:startsUpdatesOnAuthorization:)` (Task 2), `RegionsAPIService.standalone` (Task 1), `StandaloneAPIServiceProvider` (Task 3), `RegionsService.init`, `ResolvedRegionPersister`, `ResolvedRegionStore`, `UserUUID`, `Formatters`, `Bundle.appGroup/bundledRegionsFilePath/restServerAPIKey/regionsServerBaseAddress/regionsServerAPIPath/appVersion`.
- Produces: `@MainActor @Observable public final class WatchAppHost` with `locationService`, `regionsService`, `formatters`, `apiService: RESTAPIService?`, `authorizationStatus: CLAuthorizationStatus`, `refreshRegionsList()`, `static func fromMainBundle() -> WatchAppHost`; `internal func OBALoc(_:value:comment:)`. Tasks 9–10 use them.

- [ ] **Step 1: Write the localization helper**

```swift
//
//  WatchLocalization.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

fileprivate class OBAKitWatchLocalization: NSObject {}

/// Looks a string up in this framework's bundle. Same shape as OBAKitCore's
/// and OBAWidget's helpers, which are `internal` to their modules.
internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: Bundle(for: OBAKitWatchLocalization.self), value: value, comment: comment)
}
```

- [ ] **Step 2: Write the host**

```swift
//
//  WatchAppHost.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Observation
import OBAKitCore

/// The watch app's service graph. Built once by the `@main` struct and passed
/// down with `.environment(host)`; screens read `@Environment(WatchAppHost.self)`.
///
/// Deliberately not a `CoreApplication`: that initializer starts a regions
/// fetch, builds Obaco and survey services, opens and purges the GRDB stop
/// cache, and bumps the launch counter that survey gating reads. The watch
/// needs none of it. Never read `\.coreApplication` from watch code — its
/// default value builds one.
@MainActor
@Observable
public final class WatchAppHost: NSObject, LocationServiceDelegate {
    public let locationService: LocationService
    public let regionsService: RegionsService
    public let formatters: Formatters

    /// Follows `regionsService.currentRegion`; nil until a region is known.
    public private(set) var apiService: RESTAPIService?

    /// Mirrors `locationService.authorizationStatus` so views can react to a grant.
    public private(set) var authorizationStatus: CLAuthorizationStatus

    // `RegionsService` holds its delegates weakly; the host retains both.
    @ObservationIgnored private let apiServiceProvider: StandaloneAPIServiceProvider
    @ObservationIgnored private let resolvedRegionPersister: ResolvedRegionPersister

    public init(
        userDefaults: UserDefaults,
        locationService: LocationService,
        bundledRegionsFilePath: String,
        regionsServerBaseURL: URL?,
        regionsAPIPath: String?,
        apiKey: String,
        appVersion: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) {
        self.locationService = locationService
        self.formatters = Formatters(locale: .current, calendar: .current, themeColors: .shared)

        // The watch has its own client identity, shared with its widget through
        // the app-group suite. The phone's UUID is never synced.
        let uuid = UserUUID.value(in: userDefaults)

        let regionsAPIService = regionsServerBaseURL.map {
            RegionsAPIService.standalone(baseURL: $0, apiKey: apiKey, appVersion: appVersion, uuid: uuid, dataLoader: dataLoader)
        }
        let regionsService = RegionsService(
            apiService: regionsAPIService,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsFilePath,
            apiPath: regionsAPIPath
        )
        self.regionsService = regionsService

        let provider = StandaloneAPIServiceProvider(
            regionsService: regionsService,
            apiKey: apiKey,
            appVersion: appVersion,
            uuid: uuid,
            dataLoader: dataLoader
        )
        self.apiServiceProvider = provider
        self.apiService = provider.apiService

        // The step 6 watch widget reads the resolved region from the suite.
        self.resolvedRegionPersister = ResolvedRegionPersister(
            regionsService: regionsService,
            store: ResolvedRegionStore(userDefaults: userDefaults)
        )

        self.authorizationStatus = locationService.authorizationStatus

        super.init()

        provider.onChange = { [weak self] in
            guard let self else { return }
            self.apiService = self.apiServiceProvider.apiService
        }
        locationService.addDelegate(self)
    }

    /// Builds the host from `Bundle.main`'s `OBAKitConfig`, the way an app's
    /// `watch.yml` configures it.
    public static func fromMainBundle() -> WatchAppHost {
        let bundle = Bundle.main
        guard
            let appGroup = bundle.appGroup,
            let userDefaults = UserDefaults(suiteName: appGroup),
            let bundledRegionsFilePath = bundle.bundledRegionsFilePath,
            let apiKey = bundle.restServerAPIKey
        else {
            fatalError("The watch app's Info.plist needs an OBAKitConfig dictionary with AppGroup, BundledRegionsFileName, and RESTServerAPIKey; see Apps/OneBusAway/watch.yml.")
        }

        let locationService = LocationService(
            userDefaults: userDefaults,
            locationManager: CLLocationManager(),
            startsUpdatesOnAuthorization: false
        )

        return WatchAppHost(
            userDefaults: userDefaults,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsFilePath,
            regionsServerBaseURL: bundle.regionsServerBaseAddress,
            regionsAPIPath: bundle.regionsServerAPIPath,
            apiKey: apiKey,
            appVersion: bundle.appVersion
        )
    }

    /// Once per launch. `RegionsService` gates it to once a day on its own.
    public func refreshRegionsList() {
        Task { await regionsService.updateRegionsList() }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
}
```

- [ ] **Step 3: Wire the shell to the host**

Replace `WatchApp/WatchApp.swift`'s body with:

```swift
@main
struct WatchApp: App {
    @State private var host = WatchAppHost.fromMainBundle()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(host)
        }
    }
}
```

(keep the file header and the doc comment).

- [ ] **Step 4: Build for the watch simulator and for device architectures**

Both standard watch build commands. Expected: `BUILD SUCCEEDED` twice, zero warnings mentioning `OBAKitWatch/`. If `@Observable` on an `NSObject` subclass with an `@objc` delegate conformance produces an isolation error, make the delegate method `nonisolated` and hop with `MainActor.assumeIsolated` — but first read the error; `LocationServiceDelegate` is `@MainActor`, so the plain form should compile.

- [ ] **Step 5: Smoke test and commit**

```bash
scripts/watch_smoke_test "$SCRATCH/dd"
git add OBAKitWatch/WatchLocalization.swift OBAKitWatch/Host/WatchAppHost.swift WatchApp/WatchApp.swift
git commit -m "OBAKitWatch: WatchAppHost assembles the standalone services; the shell injects it"
```

Expected: `PASS`.

---

## Task 9: Nearby stops

**Files:**
- Create: `OBAKitWatch/Nearby/NearbyStopsModel.swift`, `OBAKitWatch/Nearby/NearbyStopsView.swift`, `OBAKitWatch/Nearby/NearbyStopRow.swift`, `OBAKitWatch/Shared/MessageView.swift`
- Rewrite: `OBAKitWatch/WatchRootView.swift`

**Interfaces:**
- Consumes: `WatchAppHost` (Task 8), `NearbyStopsLoader` (Task 4), `LocationService.requestLocation(desiredAccuracy:)` (Task 2), `RegionsService.physicallyLocatedRegion`, `Stop`, `OBALoc`.
- Produces: `NearbyStopsModel` (`Phase`, `phase`, `origin`, `regionName`, `refresh()`), `NearbyStopsView(model:)`, `MessageView`, `WatchRootView` with a `navigationDestination(for: Stop.self)` that Task 10 fills in.

- [ ] **Step 1: The model**

```swift
//
//  NearbyStopsModel.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Observation
import OBAKitCore

/// Drives the Nearby screen: one location fix → region check → stops.
///
/// All branching that can be tested lives in OBAKitCore (`NearbyStopsLoader`,
/// `LocationService.requestLocation`, `RegionsService`); this maps their
/// results to a `Phase`.
@MainActor
@Observable
public final class NearbyStopsModel {
    public enum Phase: Equatable {
        case awaitingAuthorization
        case locationDenied
        case locating
        case noRegion
        case failed(String)
        case empty
        case loaded([Stop])
    }

    public private(set) var phase: Phase
    /// The fix the current list was fetched around; rows show distance from it.
    public private(set) var origin: CLLocation?
    /// The region containing the last fix; the screen title.
    public private(set) var regionName: String?

    @ObservationIgnored private let host: WatchAppHost?
    @ObservationIgnored private let loader = NearbyStopsLoader()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(host: WatchAppHost) {
        self.host = host
        self.phase = .locating
    }

    /// For previews and tests: a fixed phase, no services.
    public init(phase: Phase, origin: CLLocation? = nil, regionName: String? = nil) {
        self.host = nil
        self.phase = phase
        self.origin = origin
        self.regionName = regionName
    }

    /// Re-requests location and reloads. A refresh already in flight is
    /// cancelled; the one-shot it was awaiting still resolves and is ignored.
    public func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await performRefresh() }
    }

    private func performRefresh() async {
        guard let host else { return }

        switch host.locationService.authorizationStatus {
        case .notDetermined:
            phase = .awaitingAuthorization
            host.locationService.requestInUseAuthorization()
            return
        case .denied, .restricted:
            phase = .locationDenied
            return
        default:
            break
        }

        phase = .locating

        let fix: CLLocation
        do {
            fix = try await host.locationService.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
            return
        }
        guard !Task.isCancelled else { return }
        origin = fix

        // `currentRegion` keeps the previous launch's region when a fix lands
        // outside every region, so the rule keys off where the watch *is*.
        guard let region = host.regionsService.physicallyLocatedRegion else {
            regionName = nil
            phase = .noRegion
            return
        }
        regionName = region.name

        // The fix above set currentLocation → RegionsService selected the
        // region → StandaloneAPIServiceProvider rebuilt the service → the host
        // republished it, all synchronously on the main actor.
        guard let apiService = host.apiService else {
            phase = .noRegion
            return
        }

        do {
            let stops = try await loader.stops(near: fix.coordinate, using: apiService)
            guard !Task.isCancelled else { return }
            phase = stops.isEmpty ? .empty : .loaded(stops)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: The shared message view**

```swift
//
//  MessageView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// One deliberate screen per empty or error state: an icon, a sentence, and
/// an optional action.
struct MessageView: View {
    let text: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        } description: {
            Text(text)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview("With action") {
    MessageView(text: "Something went wrong.", systemImage: "exclamationmark.triangle", actionTitle: "Retry") {}
}

#Preview("Without action") {
    MessageView(text: "No stops nearby.", systemImage: "bus")
}
```

- [ ] **Step 3: The row and the screen**

`OBAKitWatch/Nearby/NearbyStopRow.swift`:

```swift
//
//  NearbyStopRow.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

struct NearbyStopRow: View {
    let stop: Stop
    let origin: CLLocation?

    private var routeNames: [String] {
        (stop.routes ?? []).map(\.shortName)
    }

    private var distanceText: String? {
        guard let origin else { return nil }
        let meters = stop.location.distance(from: origin)
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stop.nameWithLocalizedDirectionAbbreviation)
                .font(.headline)
                .lineLimit(2)
            if !routeNames.isEmpty {
                Text(routeNames.formatted(.list(type: .and, width: .narrow)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let distanceText {
                Text(distanceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
```

`OBAKitWatch/Nearby/NearbyStopsView.swift`:

```swift
//
//  NearbyStopsView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

struct NearbyStopsView: View {
    let model: NearbyStopsModel

    var body: some View {
        content
            .navigationTitle(model.regionName ?? OBALoc("nearby.title", value: "Nearby", comment: "Screen title before a transit region is known"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(OBALoc("nearby.refresh", value: "Refresh", comment: "Toolbar button; re-requests location and reloads"), systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .awaitingAuthorization:
            MessageView(
                text: OBALoc("nearby.awaiting_authorization", value: "Allow location access to see stops near you.", comment: "Shown while the system location prompt is up"),
                systemImage: "location"
            )
        case .locationDenied:
            MessageView(
                text: OBALoc("nearby.location_denied", value: "Location access is off. Nearby stops need your location.", comment: "Shown when location is denied or restricted"),
                systemImage: "location.slash"
            )
        case .locating:
            ProgressView(OBALoc("nearby.locating", value: "Finding your location…", comment: "Progress text"))
        case .noRegion:
            MessageView(
                text: OBALoc("nearby.no_region", value: "No transit region here.", comment: "The fix is outside every supported region"),
                systemImage: "map"
            )
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: OBALoc("nearby.retry", value: "Retry", comment: "Button after a failure"),
                action: { model.refresh() }
            )
        case .empty:
            MessageView(
                text: OBALoc("nearby.empty", value: "No stops nearby.", comment: "The server returned zero stops"),
                systemImage: "bus"
            )
        case .loaded(let stops):
            List(stops) { stop in
                NavigationLink(value: stop) {
                    NearbyStopRow(stop: stop, origin: model.origin)
                }
            }
        }
    }
}

#Preview("Awaiting authorization") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .awaitingAuthorization)) }
}

#Preview("Denied") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .locationDenied)) }
}

#Preview("Locating") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .locating)) }
}

#Preview("No region") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .noRegion)) }
}

#Preview("Failed") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .failed("The request timed out."))) }
}

#Preview("Empty") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .empty, regionName: "Puget Sound")) }
}
```

(A `.loaded` preview needs a decoded `Stop`; core has no public fixture builder, so that phase is verified in the simulator instead.)

- [ ] **Step 4: The root view**

Replace `OBAKitWatch/WatchRootView.swift`:

```swift
//
//  WatchRootView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The watch app's root: one navigation stack, Nearby at the bottom of it.
/// Owns the models and the scene-phase driver so the shell stays a `@main`.
public struct WatchRootView: View {
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var nearby: NearbyStopsModel?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let nearby {
                    NearbyStopsView(model: nearby)
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: Stop.self) { stop in
                StopArrivalsView(model: StopArrivalsModel(host: host, stop: stop))
            }
        }
        .task {
            guard nearby == nil else { return }
            let model = NearbyStopsModel(host: host)
            nearby = model
            host.refreshRegionsList()
            model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // A fresh fix on every foreground; the initial launch is covered by
            // `.task`, and `onChange` does not fire for the initial value.
            if phase == .active {
                nearby?.refresh()
            }
        }
        .onChange(of: host.authorizationStatus) { _, _ in
            // The grant after the system prompt; a denial lands in `.locationDenied`.
            nearby?.refresh()
        }
    }
}
```

`StopArrivalsView` and `StopArrivalsModel` do not exist until Task 10. For this task, use a placeholder destination so the build passes:

```swift
            .navigationDestination(for: Stop.self) { stop in
                Text(stop.nameWithLocalizedDirectionAbbreviation)
            }
```

and Task 10 swaps in the real one.

- [ ] **Step 5: Build, then drive it in the simulator**

Both standard watch build commands: `BUILD SUCCEEDED`, no warnings under `OBAKitWatch/`.

Then:

```bash
WATCH_UDID=$(scripts/resolve_watch_simulator_udid) && \
xcrun simctl boot "$WATCH_UDID" 2>/dev/null; xcrun simctl bootstatus "$WATCH_UDID" -b >/dev/null && \
xcrun simctl location "$WATCH_UDID" set 47.656422,-122.312164 && \
xcodebuildmcp simulator build-and-run --project-path OBAKit.xcodeproj --scheme WatchApp --simulator-id "$WATCH_UDID" && \
sleep 5 && xcodebuildmcp simulator snapshot-ui --simulator-id "$WATCH_UDID" --style minimal
```

Expected on first launch: the awaiting-authorization message and the system location prompt. Find the prompt's "Allow Once" / "Allow While Using App" element ref in the snapshot and press it with `xcodebuildmcp ui-automation touch --simulator-id "$WATCH_UDID" --element-ref <ref> --down --up --delay 0.08` (if the `ui-automation` workflow is not enabled in this XcodeBuildMCP build, `xcodebuildmcp simulator snapshot-ui` plus `xcrun simctl` are the fallback: grant location up front with `xcrun simctl privacy "$WATCH_UDID" grant location-always org.onebusaway.iphone.watchkitapp` before launching). Re-snapshot: expected a list whose first row is "15th Ave NE & NE Campus Pkwy" (or a nearby University District stop) with a distance under 200 m, and the title "Puget Sound".

Take a screenshot of the list:

```bash
xcodebuildmcp simulator screenshot --simulator-id "$WATCH_UDID" --return-format path --style minimal
```

and copy it to `$SCRATCH/nearby-loaded.png`. Then set the location to the middle of the Pacific (`xcrun simctl location "$WATCH_UDID" set 0,-150`), press the toolbar refresh button, and expect "No transit region here." Screenshot to `$SCRATCH/nearby-noregion.png`.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh | tail -5
git add OBAKitWatch
git commit -m "OBAKitWatch: Nearby stops from a one-shot fix, with a Phase per state"
```

---

## Task 10: Stop arrivals

**Files:**
- Create: `OBAKitWatch/Arrivals/StopArrivalsModel.swift`, `OBAKitWatch/Arrivals/StopArrivalsView.swift`, `OBAKitWatch/Arrivals/ArrivalRow.swift`
- Modify: `OBAKitWatch/WatchRootView.swift` (real destination)

**Interfaces:**
- Consumes: `StopArrivalsPoller` (Task 5), `WatchAppHost.apiService`, `ArrivalDeparture` (`arrivalDepartureDate`, `predicted`, `tripHeadsign`, `routeShortName`, `route: Route!`, `scheduleStatus`), `Formatters.timeFormatter`, `.formattedTime(until:)`, `.colorForScheduleStatus(_:)`, OBAKitCore's `RouteBadgeView` and `CountdownView`, `ThemeColors.shared.brand`.
- Produces: `StopArrivalsModel(host:stop:)` with `Phase`, `startPolling()`, `stopPolling()`, `retry()`; `StopArrivalsView(model:)`.

- [ ] **Step 1: The model**

```swift
//
//  StopArrivalsModel.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

/// Drives the stop screen: a 30-second poll while the scene is active.
@MainActor
@Observable
public final class StopArrivalsModel {
    public enum Phase: Equatable {
        case loading
        case empty(updatedAt: Date)
        case failed(String)
        /// `stale` is set when a later poll failed; the list and its
        /// `updatedAt` are the last good ones.
        case loaded([ArrivalDeparture], updatedAt: Date, stale: Bool)
    }

    public let stop: Stop
    public private(set) var phase: Phase

    @ObservationIgnored private let host: WatchAppHost?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let poller = StopArrivalsPoller()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(host: WatchAppHost, stop: Stop, interval: Duration = .seconds(30)) {
        self.host = host
        self.stop = stop
        self.interval = interval
        self.phase = .loading
    }

    /// For previews and tests: a fixed phase, no services.
    public init(stop: Stop, phase: Phase) {
        self.host = nil
        self.stop = stop
        self.interval = .seconds(30)
        self.phase = phase
    }

    public func startPolling() {
        guard pollTask == nil, let host else { return }
        guard let apiService = host.apiService else {
            phase = .failed(OBALoc("arrivals.no_service", value: "No transit region selected.", comment: "Arrivals cannot load without a region"))
            return
        }

        let stream = poller.arrivals(for: stop.id, every: interval, using: apiService, clock: ContinuousClock())
        pollTask = Task { [weak self] in
            for await result in stream {
                guard let self, !Task.isCancelled else { return }
                self.apply(result)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func retry() {
        stopPolling()
        phase = .loading
        startPolling()
    }

    private func apply(_ result: Result<[ArrivalDeparture], Error>) {
        let now = Date()
        switch result {
        case .success(let arrivals):
            phase = arrivals.isEmpty ? .empty(updatedAt: now) : .loaded(arrivals, updatedAt: now, stale: false)
        case .failure(let error):
            switch phase {
            case .loaded(let arrivals, let updatedAt, _):
                phase = .loaded(arrivals, updatedAt: updatedAt, stale: true)
            case .empty:
                break
            case .loading, .failed:
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 2: The row**

```swift
//
//  ArrivalRow.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct ArrivalRow: View {
    let arrival: ArrivalDeparture
    let formatters: Formatters

    private var headsign: String {
        arrival.tripHeadsign ?? arrival.routeShortName
    }

    private var routeColor: Color {
        Color(uiColor: arrival.route?.color ?? ThemeColors.shared.brand)
    }

    private var routeTextColor: Color? {
        arrival.route?.textColor.map { Color(uiColor: $0) }
    }

    private var countdownColor: Color {
        Color(uiColor: formatters.colorForScheduleStatus(arrival.scheduleStatus))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RouteBadgeView(routeShortName: arrival.routeShortName, routeColor: routeColor, routeTextColor: routeTextColor, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(headsign)
                    .font(.caption)
                    .lineLimit(2)
                Text(formatters.timeFormatter.string(from: arrival.arrivalDepartureDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            CountdownView(departure: arrival.arrivalDepartureDate, isRealTime: arrival.predicted, color: countdownColor, emphasized: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: OBALoc("arrivals.row.a11y_fmt", value: "%1$@ to %2$@, %3$@", comment: "VoiceOver: route, headsign, time until departure"),
                arrival.routeShortName, headsign, formatters.formattedTime(until: arrival)
            )
        )
    }
}
```

- [ ] **Step 3: The screen**

```swift
//
//  StopArrivalsView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct StopArrivalsView: View {
    let model: StopArrivalsModel
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(model.stop.nameWithLocalizedDirectionAbbreviation)
            .onAppear { model.startPolling() }
            .onDisappear { model.stopPolling() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.startPolling()
                } else {
                    model.stopPolling()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(OBALoc("arrivals.loading", value: "Loading departures…", comment: "Progress text"))
        case .empty(let updatedAt):
            VStack(spacing: 8) {
                MessageView(
                    text: OBALoc("arrivals.empty", value: "No departures in the next 60 minutes.", comment: "Empty state"),
                    systemImage: "bus"
                )
                updatedAtText(updatedAt)
            }
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: OBALoc("nearby.retry", value: "Retry", comment: "Button after a failure"),
                action: { model.retry() }
            )
        case .loaded(let arrivals, let updatedAt, let stale):
            List {
                Section {
                    ForEach(arrivals) { arrival in
                        ArrivalRow(arrival: arrival, formatters: host.formatters)
                    }
                } footer: {
                    updatedAtText(updatedAt)
                        .foregroundStyle(stale ? .orange : .secondary)
                }
            }
        }
    }

    private func updatedAtText(_ date: Date) -> Text {
        Text(String(
            format: OBALoc("arrivals.updated_at_fmt", value: "Updated at %@", comment: "%@ is a short time, e.g. 3:42 PM"),
            host.formatters.timeFormatter.string(from: date)
        ))
        .font(.caption2)
    }
}
```

`ArrivalDeparture` is `Identifiable`, so `ForEach(arrivals)` needs no `id:`.

- [ ] **Step 4: Wire the destination**

In `OBAKitWatch/WatchRootView.swift`, replace the placeholder destination with:

```swift
            .navigationDestination(for: Stop.self) { stop in
                StopArrivalsView(model: StopArrivalsModel(host: host, stop: stop))
            }
```

- [ ] **Step 5: Build and drive**

Both standard watch build commands: `BUILD SUCCEEDED`. Then relaunch with the Seattle location as in Task 9, tap the first stop row (`touch --down --up` on its ref), and expect within a few seconds a list of departures with route badges and ticking countdowns and an "Updated at" footer. Screenshot to `$SCRATCH/arrivals-loaded.png`. Wait 35 seconds and confirm in `xcodebuildmcp simulator` logs (the build-and-run output names the log file) or by a second screenshot that "Updated at" advanced. Navigate back; confirm Nearby is still shown.

- [ ] **Step 6: Lint and commit**

```bash
scripts/swiftlint.sh | tail -5
git add OBAKitWatch
git commit -m "OBAKitWatch: stop arrivals with a 30-second poll while the scene is active"
```

---

## Task 11: Strings in 13 locales and the source-tree parity test

**Files:**
- Modify: `scripts/extract_strings`
- Create: `OBAKitWatch/Strings/<locale>.lproj/Localizable.strings` ×13
- Create: `OBAKitTests/Strings/WatchLocalizationTests.swift`

**Interfaces:**
- Consumes: every `OBALoc` call in `OBAKitWatch/` (Tasks 9–10), the English table in this plan's header.
- Produces: the 13 tables; a test that fails when any locale drifts from `en`.

- [ ] **Step 1: Extend `scripts/extract_strings`**

Append:

```bash

mkdir -p OBAKitWatch/Strings/en.lproj
find OBAKitWatch -name "*.swift" -print0 | xargs -0 genstrings -s OBALoc -o OBAKitWatch/Strings/en.lproj
iconv -f UTF-16 -t UTF-8 OBAKitWatch/Strings/en.lproj/Localizable.strings > OBAKitWatch/Strings/en.lproj/Localizable.strings.new
mv -f OBAKitWatch/Strings/en.lproj/Localizable.strings.new OBAKitWatch/Strings/en.lproj/Localizable.strings
```

Then run **only the new block** (the first two blocks rewrite `%3$02d` and orphan a key today; see PR #1447's body — do not run them):

```bash
mkdir -p OBAKitWatch/Strings/en.lproj && \
find OBAKitWatch -name "*.swift" -print0 | xargs -0 genstrings -s OBALoc -o OBAKitWatch/Strings/en.lproj && \
iconv -f UTF-16 -t UTF-8 OBAKitWatch/Strings/en.lproj/Localizable.strings > /tmp/watch-en.strings && mv -f /tmp/watch-en.strings OBAKitWatch/Strings/en.lproj/Localizable.strings && \
grep -c '" = "' OBAKitWatch/Strings/en.lproj/Localizable.strings && git status --short | grep -v "^?? OBAKitWatch/Strings" 
```

Expected: 13 keys (the table in the plan header), and no other tracked strings file changed. Compare the generated keys and values to the header table; any mismatch means a view used a different key or value — fix the **view** to match the table.

- [ ] **Step 2: Write the 12 translations**

For each of `ar es fil fr it ko pl pt-BR ru vi zh-Hans zh-Hant`, create `OBAKitWatch/Strings/<locale>.lproj/Localizable.strings` with exactly the 13 keys from `en.lproj`, in the same order, with the same `/* comment */` lines and translated values. Rules: keep `%@`, `%1$@`, `%2$@`, `%3$@` verbatim; keep the trailing period where English has one; use the same register as the existing translations in `OBAKitCore/Strings/<locale>.lproj/Localizable.strings` (read that file's `stop_page.empty.no_departures_fmt`, `common.retry` if present, and `map_controller.*` entries for vocabulary such as "stop", "departure", "location", "region", and reuse the same words). The translator is the implementer; take the time to produce natural, correct sentences, not word-for-word English.

- [ ] **Step 3: Write the failing parity test**

```swift
//
//  WatchLocalizationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing

/// Parity checks for OBAKitWatch's strings, read from the **source tree**.
///
/// `LocalizationTests` loads each framework's bundle, which an iOS-hosted test
/// cannot do for a watchOS framework. The tables are plain plists on disk,
/// so this suite parses them relative to `#filePath` instead.
@Suite(.serialized)
struct WatchLocalizationTests {

    private static let locales = ["ar", "en", "es", "fil", "fr", "it", "ko", "pl", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"]

    /// `%@`, `%d`, `%1$@`, `%2$d`, … and the escaped `%%`.
    // swiftlint:disable:next force_try
    private static let specifier = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfs]|%%"#)

    private static var repoRoot: URL {
        // OBAKitTests/Strings/WatchLocalizationTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func strings(locale: String) -> [String: String]? {
        let url = repoRoot.appending(path: "OBAKitWatch/Strings/\(locale).lproj/Localizable.strings")
        return NSDictionary(contentsOf: url) as? [String: String]
    }

    private static func specifiers(in value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        return specifier.matches(in: value, range: range)
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
            .sorted()
    }

    @Test func `English table exists and is not empty`() throws {
        let english = try #require(Self.strings(locale: "en"))
        #expect(english.count >= 10)
    }

    @Test func `Every locale has the same keys as English`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else {
                Issue.record("OBAKitWatch/\(locale): no Localizable.strings")
                continue
            }
            let missing = Set(english.keys).subtracting(translated.keys)
            let extra = Set(translated.keys).subtracting(english.keys)
            #expect(missing.isEmpty, "OBAKitWatch/\(locale) is missing \(missing.sorted())")
            #expect(extra.isEmpty, "OBAKitWatch/\(locale) has keys not in en: \(extra.sorted())")
        }
    }

    @Test func `Every locale keeps the same format specifiers`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else { continue }
            for (key, value) in english {
                guard let other = translated[key] else { continue }
                #expect(Self.specifiers(in: value) == Self.specifiers(in: other), "OBAKitWatch/\(locale)/\(key): specifiers differ")
            }
        }
    }

    @Test func `No locale still carries an untranslated English value`() throws {
        let english = try #require(Self.strings(locale: "en"))
        for locale in Self.locales where locale != "en" {
            guard let translated = Self.strings(locale: locale) else { continue }
            let untranslated = english.filter { key, value in translated[key] == value && value.count > 3 }.keys.sorted()
            #expect(untranslated.isEmpty, "OBAKitWatch/\(locale) still has English for \(untranslated)")
        }
    }

    @Test func `The watch app's location purpose string is translated in every locale`() {
        for locale in Self.locales where locale != "en" {
            let url = Self.repoRoot.appending(path: "WatchApp/\(locale).lproj/InfoPlist.strings")
            let table = NSDictionary(contentsOf: url) as? [String: String]
            #expect(table?["NSLocationWhenInUseUsageDescription"]?.isEmpty == false, "WatchApp/\(locale): missing NSLocationWhenInUseUsageDescription")
        }
    }
}
```

- [ ] **Step 4: Run it**

`scripts/generate_project OneBusAway` (new test file), then `SUITE_NAME=WatchLocalizationTests`. Expected: 5 passed. A failure names the locale and key; fix the table, not the test.

- [ ] **Step 5: Commit**

```bash
git add scripts/extract_strings OBAKitWatch/Strings OBAKitTests/Strings/WatchLocalizationTests.swift
git commit -m "OBAKitWatch strings in 13 locales, extracted by scripts/extract_strings and checked from the source tree"
```

---

## Task 12: CI

**Files:**
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: `scripts/watch_smoke_test`, `scripts/resolve_watch_simulator_udid`, the `WatchApp` scheme, `scripts/generate_project KiedyBus`.

- [ ] **Step 1: Move the watchOS platform guard ahead of the iOS build**

Cut the whole `- name: Download watchOS platform (if needed)` step (with its comment block) and paste it immediately **before** `- name: Generate xcodeproj for OneBusAway`, removing its `if: success() || failure()` line (it now gates the build). Update its comment's first sentence to: `# Needed before the iOS build now: App depends on WatchApp, so building the App scheme compiles the watch stack's simulator slices.`

- [ ] **Step 2: Widen the device compile and add the smoke test and the KiedyBus check**

Replace the `- name: Build OBAKitCore for watchOS (arm64 + arm64_32)` step with:

```yaml
    - name: Build WatchApp for watchOS devices (arm64 + arm64_32)
      if: success() || failure()
      timeout-minutes: 25
      run: |
        set -o pipefail
        xcodebuild build \
          -project 'OBAKit.xcodeproj' \
          -scheme 'WatchApp' \
          -destination 'generic/platform=watchOS' \
          -derivedDataPath DerivedData \
          CODE_SIGNING_ALLOWED=NO \
          -quiet \
          | tee xcodebuild-watchos.log

    # A compile cannot catch dyld, Info.plist, or embedding failures: the
    # missing-LD_RUNPATH_SEARCH_PATHS crash builds green. `simctl launch` and
    # XcodeBuildMCP both report success for an app dyld kills, so the script
    # asserts liveness after a delay. Unpaired watch simulator; OneBusAway only.
    - name: Watch app launch smoke test
      if: success() || failure()
      timeout-minutes: 15
      run: scripts/watch_smoke_test DerivedData

    # Last, because generating another app replaces the root project.yml and
    # OBAKit.xcodeproj. An app with no watch.yml must generate exactly the
    # project it generated before the watch targets existed.
    - name: KiedyBus generates no watch targets
      if: success() || failure()
      run: |
        set -euo pipefail
        scripts/generate_project KiedyBus
        if xcodegen dump --type json | python3 -c 'import json,sys; sys.exit(0 if "WatchApp" in json.load(sys.stdin)["targets"] else 1)'; then
          echo "KiedyBus resolved spec unexpectedly contains WatchApp" >&2
          exit 1
        fi
        echo "KiedyBus: no watch targets"
```

Update the comment above the renamed step so its first line reads `# watchOS device-architecture compile of every watch target (see the watchOS` and keep the rest.

- [ ] **Step 3: Validate the YAML and the step order locally**

```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/tests.yml')); print([s['name'] for s in d['jobs']['build']['steps'] if 'name' in s])"
```

Expected: the list shows `Download watchOS platform (if needed)` before `Generate xcodeproj for OneBusAway`, and the three new steps after `OBAKit Unit Test`. (If `yaml` is not installed: `pip3 install pyyaml`, or read the file by eye.) Also run `bash -n scripts/watch_smoke_test`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/tests.yml
git commit -m "CI: platform guard before the iOS build, WatchApp device compile, launch smoke test, KiedyBus no-watch check"
```

---

## Task 13: Docs, full verification, size

**Files:**
- Modify: `CLAUDE.md`, `README.markdown`

- [ ] **Step 1: Document the commands**

`CLAUDE.md`, "Project Generation" block: add `scripts/generate_project OneBusAway --no-watch   # iOS only; no watchOS platform needed`, and one paragraph after the block:

> The OneBusAway project includes two watchOS targets, `OBAKitWatch` (framework) and `WatchApp` (shell), opted in through `Apps/OneBusAway/watch.yml`. Building the `App` scheme also builds them, so a machine without the watchOS platform must pass `--no-watch`. Build the watch app with `WATCH_UDID=$(scripts/resolve_watch_simulator_udid)` and `-scheme WatchApp -destination "platform=watchOS Simulator,id=$WATCH_UDID"`; `scripts/watch_smoke_test` installs, launches, and asserts it stays alive, which a compile cannot. Watch code never builds a `CoreApplication` and never reads `\.coreApplication`; `OBAKitWatch/Host/WatchAppHost.swift` is the assembly.

Add to "Framework Structure": `- **OBAKitWatch**: watchOS UI framework (SwiftUI). Host, models, and screens; logic stays in OBAKitCore so OBAKitTests covers it.` and `- **WatchApp**: watchOS application shell. White-label; per-app identity comes from Apps/<App>/watch.yml.`

`README.markdown`: after the `scripts/setup` line in Quick Start, add `# add --no-watch to scripts/generate_project for iOS-only builds without the watchOS platform`.

- [ ] **Step 2: Full unit suite, lint, all builds**

```bash
scripts/generate_project OneBusAway && SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && set -o pipefail && \
xcodebuild test -project OBAKit.xcodeproj -scheme App -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:OBAKitTests 2>&1 | grep -E "Test Suite|passed|failed|error:" | tail -15
```

Expected: every suite passes; note the totals for the PR body (the step 3 baseline was 2,758 tests / 296 suites; expect about +25 tests / +6 suites). Then `scripts/swiftlint.sh | tail -3` (clean), the watch simulator build, the device-architecture build, and `scripts/watch_smoke_test` (PASS).

- [ ] **Step 3: Measure the unthinned release size**

```bash
set -o pipefail && xcodebuild build -project OBAKit.xcodeproj -scheme WatchApp -configuration Release \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath "$SCRATCH/rel" -quiet 2>&1 | tail -3; \
du -sh "$SCRATCH/rel/Build/Products/Release-watchos/WatchApp.app"; \
du -sh "$SCRATCH/rel/Build/Products/Release-watchos/WatchApp.app/Frameworks/"*
```

Record the numbers for the PR body against the 25 MB budget (unthinned, both architectures).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.markdown
git commit -m "Document the watch targets, --no-watch, and the smoke test"
```

The PR body (written by the `/go` wrap-up) records: the test totals, the size, the two screenshots' findings, the negative probes from Tasks 6 and 7, and the three things not verified (32-bit runtime, network routes, thinned size).
