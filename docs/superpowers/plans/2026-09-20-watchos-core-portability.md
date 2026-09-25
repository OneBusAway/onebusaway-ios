# watchOS Core Portability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OBAKitCore build for watchOS (device architectures included) without changing iOS behavior, and give widgets a stateless arrivals path that fixes the iOS widget's six-hour staleness and its custom-region gap.

**Architecture:** One `OBAKitCore` module compiled from two directories: the existing `OBAKitCore/` (portable, iOS + watchOS) and a new sibling `OBAKitCoreiOS/` (iOS-only, same module, so no `import` changes anywhere). Six small seam fixes remove the watchOS-unavailable API from the portable tree. A stateless, streaming `BookmarkArrivalsLoader` plus a persisted resolved `Region` let widget extensions fetch arrivals without building a `CoreApplication`.

**Tech Stack:** Swift 6 language mode, XcodeGen 2.46.0 (YAML), Swift Testing, WidgetKit, SwiftLint 0.65.1, GitHub Actions (`xcode-27` image).

**Spec:** `docs/superpowers/specs/2026-09-20-watchos-architecture-design.md` — this plan implements its sequencing **steps 1–3**. Step 0 (Live Activity families) and steps 4–6 (sync, watch app, watch widget) get their own plans.

## Global Constraints

- iOS deployment target stays **18.0**. watchOS deployment target is **11.0**, set as `WATCHOS_DEPLOYMENT_TARGET: "11.0"` — never as a `deploymentTarget: {iOS:…, watchOS:…}` map, which XcodeGen silently drops on a `supportedDestinations` target.
- **`Int` is 32 bits on most watches** (`arm64_32`). Watch simulators are 64-bit and hide it. Never decode an epoch value into `Int`; use `Int64` or `Date`. The only check that catches this class is a build for `-destination 'generic/platform=watchOS'`.
- OBAKitCore stays **application-extension safe** (`APPLICATION_EXTENSION_API_ONLY: true`) and keeps `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`. Every other target is MainActor-default. The five concurrency diagnostic groups are **errors**.
- **No `import` statement changes.** Both directories are the `OBAKitCore` module.
- `Apps/Shared/app_shared.yml` is **not modified**.
- The portable tree gains exactly **two** platform conditionals: `#if canImport(ActivityKit)` in `CoreApplication.swift`, and `#if !os(watchOS)` in `ThemeColors.swift`. Anything else iOS-only goes in `OBAKitCoreiOS/`.
- `destinationFilters` works **only** on a sibling directory with `type: group`. It is silently ignored on `syncedFolder` sources, and a `type: group` nested inside the synced root breaks the iOS build.
- Tests are **Swift Testing** (`@Suite` / `@Test` / `#expect`), in the iOS-hosted `OBAKitTests` target. Logic goes in OBAKitCore so that target can test it.
- Run `scripts/generate_project OneBusAway` before every build, and **always after adding, moving, or deleting a file**, or new tests run zero times and `OBAKitCoreiOS/` files are not picked up.
- Resolve `SIMULATOR_UDID=$(scripts/resolve_simulator_udid)` **in the same shell invocation** that uses it.
- Never pipe `xcodebuild` into `tail`/`grep` without `set -o pipefail`; the pipe masks a failed build.
- A failing test run can stall for up to 10 minutes in `simctl diagnose` after the failures print. Once the failures are on screen, kill `xcodebuild`.
- Each PR leaves `main` green. Commit messages carry no attribution lines. Commit as `aaron@brethorsting.com`.
- The repo ships as white-label frameworks: no string literal containing `OneBusAway` in `OBAKit/`, `OBAKitCore/`, `OBAKitCoreiOS/`, or `OBAWidget/` (SwiftLint `hardcoded_app_name`, severity error).

### Standard commands

Run one suite (substitute the suite's class or struct name):

```bash
scripts/generate_project OneBusAway && \
SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && \
set -o pipefail && \
xcodebuild test -project OBAKit.xcodeproj -scheme App \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:OBAKitTests/SUITE_NAME 2>&1 | tail -40
```

Run the whole unit suite: the same command with `-only-testing:OBAKitTests`.

Build OBAKitCore for watchOS **device** architectures (available from Task 8 on):

```bash
scripts/generate_project OneBusAway && \
set -o pipefail && \
xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" | sort -u | tail -60
```

`-continueBuildingAfterErrors` is **not** a valid `xcodebuild` flag (exit 64, nothing compiles). If a watchOS build reports exactly one error mentioning `Clang dependency scanning failure` or `Unable to resolve module dependency: 'ActivityKit'`, the module never compiled: an `import ActivityKit` file is still in the watchOS build.

## Deviations from the spec, decided while planning

Reading the code for this plan turned up four places where the spec cannot be followed literally. Each is resolved here; the spec sentence for the first has been corrected to match.

1. **"Dedupe by stop" contradicts "`BookmarkDataLoaderTests` pass unmodified."** All three tests build their N bookmarks from one `ArrivalDeparture`, so every bookmark shares a stop, and they assert one request *per bookmark* (`requestCounter.count == 2`, `== 3`). With dedupe those become 1. Resolution: **dedupe stays** — it is the spec's stated intent — and the tests' private bookmark *builder* changes to give each bookmark a distinct stop. **Every test body and every assertion stays byte-identical**; that is the exit criterion (Task 13).
2. **`Theme.swift` does not move.** After `ThemeColors` is split out, what remains is `ThemeMetrics`, which compiled for watchOS with zero errors and is used by portable SwiftUI views. It stays in the portable tree. `UIKit/` therefore receives 11 files, not 14 (two more go to `LiveActivities/`).
3. **`DepartureSnapshot` and `OBAWidgetShared/` are deferred to the step-6 plan.** The iOS widget's views render `ArrivalDeparture` through `Formatters` today, and nothing in steps 1–3 consumes a snapshot type. This plan makes entries carry `[ArrivalDeparture]` and puts the entry-spacing and reload arithmetic in OBAKitCore (`WidgetTimelinePlanner`, Task 14), where `OBAKitTests` can reach it and where the watch widget will reuse it.
4. **The "overnight, first scheduled departure minus 15 minutes" reload rule is deferred.** It needs schedule data; the arrivals call returns only the next 60 minutes. This plan implements the two rules that data supports: 30 minutes when departures exist, 60 minutes when none do.

Known limitation carried forward, unchanged by this plan: `ArrivalDeparture.arrivalDepartureMinutes` reads the clock at render time (`timeIntervalSinceNow`), so a widget entry rendered ahead of its display date shows minutes relative to render time. Per-entry filtering (Task 15) removes departed buses from later entries; minute text accuracy is step-6 work (`Text(timerInterval:countsDown:)`).

## File Structure

**PR 1 — seam fixes in place (spec step 1).** No directory moves.

| File | Change | Responsibility |
|---|---|---|
| `OBAKitCore/Models/REST/RESTAPIResponse.swift` | modify | `currentTime` becomes `Int64?` |
| `OBAKitCore/Models/REST/TripStatus.swift` | modify | `lastLocationUpdateTime` becomes `Int64` |
| `OBAKitCore/Models/REST/References/ServiceAlert.swift` | modify | `TimeWindow` decodes through `Int64` |
| `OBAKitCore/Models/REST/ScheduleForRoute.swift` | modify | lint suppressions with reasons (seconds-of-day, safe) |
| `.swiftlint.yml` | modify | two custom rules against epoch-in-`Int` |
| `OBAKitCore/Network/APIService/APIService+GetData.swift` | modify | CFNetwork domain literal |
| `OBAKitCore/Location/Location/LocationManagerProtocol.swift` | modify | drop the four region-monitoring requirements |
| `OBAKitCore/Location/Location/RegionMonitoringLocationManager.swift` | create | the iOS-only protocol refinement |
| `OBAKitCore/Location/Location/LocationService+ProximityAlerts.swift` | create | all proximity/geofence code, as an extension |
| `OBAKitCore/Location/Location/LocationService.swift` | modify | `locationManager`, `delegates` become internal; proximity code removed |
| `OBAKitCore/Theme/ThemeColors.swift` | create | `ThemeColors`, portable, with a fixed watch palette |
| `OBAKitCore/Theme/Theme.swift` | modify | keeps only `ThemeMetrics` |
| `OBAKitCore/Orchestration/CoreApplication.swift` | modify | `#if canImport(ActivityKit)` around two lazy vars |
| `OBAKitCore/Models/Helpers/Polyline.swift` | modify | lift the `#if !os(watchOS)` fence |

**PR 2 — the second directory and the watchOS destination (spec step 2).**

| File | Change | Responsibility |
|---|---|---|
| `OBAKitCoreiOS/UIKit/` (11 files) | move | UIKit view code |
| `OBAKitCoreiOS/LiveActivities/` (10 files) | move | everything that imports or renders ActivityKit |
| `OBAKitCoreiOS/Location/` (2 files) | move | the two files Task 3 created |
| `OBAKitCore/project.yml` | modify | `supportedDestinations`, second source, `WATCHOS_DEPLOYMENT_TARGET`, exclude `project.yml` |
| `scripts/extract_strings` | modify | scan both directories |
| `.swiftlint.yml` | modify | lint `OBAKitCoreiOS` |
| `.github/workflows/tests.yml` | modify | permanent device-architecture compile step |
| `CLAUDE.md` | modify | document the two-directory rule |

**PR 3 — stateless arrivals and the iOS widget (spec step 3).**

| File | Change | Responsibility |
|---|---|---|
| `OBAKitCore/Orchestration/UserUUID.swift` | create | static UUID helper over a defaults suite |
| `OBAKitCore/Location/Regions/ResolvedRegionStore.swift` | create | read/write the resolved `Region` in a suite, with bundled fallback |
| `OBAKitCore/Location/Regions/ResolvedRegionPersister.swift` | create | `RegionsServiceDelegate` that writes on the four triggers |
| `OBAKitCore/Location/Regions/RegionsService.swift` | modify | new `updatedCustomRegions` delegate callback |
| `OBAKit/Orchestration/Application.swift` | modify | owns the persister |
| `OBAKitCore/Bookmarks/BookmarkArrivalsLoader.swift` | create | request type, streaming loader, standalone service factory |
| `OBAKitCore/Bookmarks/TripBookmarkKey.swift` | modify | `Sendable` |
| `OBAKitCore/Bookmarks/BookmarkDataLoader.swift` | modify | adopts the loader |
| `OBAKitCore/Bookmarks/WidgetTimelinePlanner.swift` | create | pure entry-date and reload-date arithmetic |
| `OBAWidget/Provider/WidgetDataProvider.swift` | rewrite | stateless; no `CoreApplication` |
| `OBAWidget/Provider/BookmarkTimelineProvider.swift` | modify | planner-driven timeline, `.after` policy |
| `OBAWidget/Entries/BookmarkEntry.swift` | modify | carries departures and `fetchedAt` |
| `OBAWidget/Widgets/OBAWidgetEntryView.swift`, `OBAWidget/Widgets/OBAWidget.swift`, `OBAWidget/Views/WidgetRowView.swift` | modify | read from the entry, not a singleton |

---

# PR 1 — Seam fixes in place

Branch: `watchos/step-1-seam-fixes` from `main`. Every task here is a refactor whose iOS behavior is unchanged; the watchOS payoff is proven in PR 2.

### Task 1: 32-bit-safe epoch fields (seam 6)

**Files:**
- Modify: `OBAKitCore/Models/REST/RESTAPIResponse.swift:18,29`
- Modify: `OBAKitCore/Models/REST/TripStatus.swift:64,172`
- Modify: `OBAKitCore/Models/REST/References/ServiceAlert.swift:133-155`
- Modify: `OBAKitCore/Models/REST/ScheduleForRoute.swift:181-182`
- Modify: `.swiftlint.yml`
- Test: `OBAKitTests/Modeling/Model Unit Tests/EpochWidthTests.swift` (create)

**Interfaces:**
- Produces: `CoreRESTAPIResponse.currentTime: Int64?`, `TripStatus.lastLocationUpdateTime: Int64`. Both are source-compatible with integer literals and with `==` against literals, so no caller changes (there are no non-test readers of either property).

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Modeling/Model Unit Tests/EpochWidthTests.swift`:

```swift
//
//  EpochWidthTests.swift
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

/// `Int` is 32 bits on `arm64_32` Apple Watches, and no simulator has that
/// width. These tests pin the *declared* type of every epoch-valued field,
/// which is the only thing a 64-bit test host can check.
@Suite struct EpochWidthTests {

    @Test func `currentTime is declared Int64`() throws {
        let data = Fixtures.loadData(file: "current_time.json")
        let response = try JSONDecoder.RESTDecoder().decode(CoreRESTAPIResponse.self, from: data)

        #expect(type(of: response.currentTime) == Int64?.self)
        #expect(response.currentTime == 1343587068277)
    }

    @Test func `lastLocationUpdateTime is declared Int64 and holds epoch milliseconds`() throws {
        let statusData: [String: Any] = [
            "activeTripId": "active_trip_123",
            "blockTripSequence": 3,
            "closestStop": "stop_closest",
            "closestStopTimeOffset": -120,
            "distanceAlongTrip": 2500.75,
            "lastKnownDistanceAlongTrip": 2480,
            "lastKnownLocation": ["lat": 47.6097, "lon": -122.3331],
            "lastKnownOrientation": 145.5,
            "lastLocationUpdateTime": 1588888744000,
            "lastUpdateTime": 1588888744000,
            "nextStop": "stop_next",
            "nextStopTimeOffset": 180,
            "orientation": 150.0,
            "phase": "IN_PROGRESS",
            "position": ["lat": 47.6098, "lon": -122.3332],
            "predicted": true,
            "scheduleDeviation": -45,
            "scheduledDistanceAlongTrip": 2545.75,
            "serviceDate": 1234512000,
            "situationIds": ["alert_trip_1"],
            "status": "default",
            "totalDistanceAlongTrip": 15000.0,
            "vehicleId": "vehicle_789"
        ]

        let status = try Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)

        #expect(type(of: status.lastLocationUpdateTime) == Int64.self)
        #expect(status.lastLocationUpdateTime == 1588888744000)
    }

    /// Passes before and after the change on a 64-bit host. It pins the
    /// seconds-versus-milliseconds heuristic across the type change.
    @Test func `Service alert time window accepts seconds and milliseconds`() throws {
        let json = Data(#"{"from": 1589553926433, "to": 1589553999}"#.utf8)
        let window = try JSONDecoder().decode(ServiceAlert.TimeWindow.self, from: json)

        #expect(window.from == Date(timeIntervalSince1970: 1589553926.433))
        #expect(window.to == Date(timeIntervalSince1970: 1589553999))
    }

    @Test func `Service alert time window without an end is open ended`() throws {
        let json = Data(#"{"from": 1589553926}"#.utf8)
        let window = try JSONDecoder().decode(ServiceAlert.TimeWindow.self, from: json)

        #expect(window.to == .distantFuture)
    }
}
```

- [ ] **Step 2: Run the tests to verify the two type tests fail**

Run the standard suite command with `-only-testing:OBAKitTests/EpochWidthTests`.
Expected: `currentTime is declared Int64` and `lastLocationUpdateTime is declared Int64…` FAIL (`type(of:)` is `Optional<Int>` / `Int`); the two `TimeWindow` tests PASS.

- [ ] **Step 3: Change the three declarations**

`OBAKitCore/Models/REST/RESTAPIResponse.swift` — replace the property and its decode line:

```swift
    /// Epoch milliseconds. `Int64`, not `Int`: `Int` is 32 bits on `arm64_32`
    /// Apple Watches and this value does not fit.
    public let currentTime: Int64?
```

```swift
        currentTime = try container.decodeIfPresent(Int64.self, forKey: .currentTime)
```

`OBAKitCore/Models/REST/TripStatus.swift` — line 64 and line 172:

```swift
    public let lastLocationUpdateTime: Int64
```

```swift
        lastLocationUpdateTime = try container.decode(Int64.self, forKey: .lastLocationUpdateTime)
```

Keep the existing doc comment above line 64; append the sentence "`Int64`, not `Int`: this is epoch milliseconds and `Int` is 32 bits on `arm64_32` watches."

`OBAKitCore/Models/REST/References/ServiceAlert.swift` — replace `decodeUnixTimestamp` and the two decode calls in `init(from:)`:

```swift
        /// Decodes a Unix timestamp that may be expressed
        /// in seconds or milliseconds.
        ///
        /// Typed over `Int64`: the threshold literal alone overflows a 32-bit
        /// `Int`, which is what `Int` is on `arm64_32` Apple Watches.
        private static func decodeUnixTimestamp(_ value: Int64) -> Date {
            let seconds: TimeInterval

            if value > 10_000_000_000 {
                seconds = TimeInterval(value) / 1_000
            } else {
                seconds = TimeInterval(value)
            }
            return Date(timeIntervalSince1970: seconds)
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawFrom = try container.decode(Int64.self, forKey: .from)
            self.from = Self.decodeUnixTimestamp(rawFrom)
            if let rawTo = try container.decodeIfPresent(Int64.self, forKey: .to) {
                self.to = Self.decodeUnixTimestamp(rawTo)
            } else {
                self.to = .distantFuture
            }
        }
```

- [ ] **Step 4: Add the SwiftLint rules**

In `.swiftlint.yml`, under `custom_rules:`, after `hardcoded_app_name`, add:

```yaml
  epoch_decoded_as_int:
    name: "Epoch value decoded as Int"
    # `Int` is 32 bits on arm64_32 Apple Watches (every watch on watchOS 11; Series
    # 6-8, SE 2, and Ultra 1 on any version). Watch simulators are 64-bit, so a
    # time-valued `Int` decodes fine everywhere except on a customer's wrist.
    # Decode epoch values as Int64 or Date. A key that merely *sounds* temporal
    # (seconds since midnight, an offset) may suppress this with
    # `// swiftlint:disable:next epoch_decoded_as_int` and a reason.
    included: "OBAKitCore(iOS)?/.*\\.swift"
    regex: 'decode(IfPresent)?\(Int\.self, forKey: \.\w*([Tt]ime|[Dd]ate|[Tt]imestamp)\b'
    message: "Decode epoch values as Int64 or Date — Int is 32 bits on arm64_32 Apple Watches."
    severity: error
  epoch_narrowed_to_int:
    name: "timeIntervalSince1970 narrowed to Int"
    included: "OBAKitCore(iOS)?/.*\\.swift"
    regex: '\bInt\([^)]*timeIntervalSince1970'
    message: "Use Int64(…) — Int is 32 bits on arm64_32 Apple Watches, and seconds-since-1970 overflows it in 2038."
    severity: error
```

`OBAKitCore/Models/REST/ScheduleForRoute.swift:181-182` decodes `arrivalTime` and `departureTime` as `Int`. Those are seconds since midnight (see `arrivalDate(for:)` a few lines below), so they are safe and the rule's name match is a false positive. Suppress with the reason:

```swift
            // Seconds since midnight, not an epoch value — fits a 32-bit Int.
            // swiftlint:disable:next epoch_decoded_as_int
            arrivalTime = try container.decode(Int.self, forKey: .arrivalTime)
            // swiftlint:disable:next epoch_decoded_as_int
            departureTime = try container.decode(Int.self, forKey: .departureTime)
```

- [ ] **Step 5: Verify lint and tests**

Run: `swiftlint lint --quiet | grep -E "epoch_|error" ; echo "lint exit: ${PIPESTATUS[0]}"`
Expected: no `epoch_` lines, no errors.

Prove the rule bites: temporarily change `Int64.self` back to `Int.self` on the `currentTime` line, run `swiftlint lint --quiet OBAKitCore/Models/REST/RESTAPIResponse.swift`, expect one `epoch_decoded_as_int` error, then restore the line.

Run `-only-testing:OBAKitTests/EpochWidthTests`, then `-only-testing:OBAKitTests/TripStatusTests`, `-only-testing:OBAKitTests/CurrentTimeModelOperationTests`, and `-only-testing:OBAKitTests/VehicleStatusModelOperationTests`.
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add OBAKitCore/Models/REST .swiftlint.yml "OBAKitTests/Modeling/Model Unit Tests/EpochWidthTests.swift"
git commit -m "Decode epoch fields as Int64 so they fit a 32-bit watch Int"
```

### Task 2: Drop the CFNetwork symbol (seam 4)

**Files:**
- Modify: `OBAKitCore/Network/APIService/APIService+GetData.swift:111-121`
- Test: `OBAKitTests/Networking/CaptivePortalDetectionTests.swift` (create)

**Interfaces:**
- Consumes: `APIService.errorLooksLikeCaptivePortal(_:)` (existing, internal, `nonisolated`).

- [ ] **Step 1: Write the pinning test**

watchOS has no CFNetwork, so `kCFErrorDomainCFNetwork` does not exist there. Its value is the string `"kCFErrorDomainCFNetwork"`. This test pins the behavior so the literal cannot drift.

Create `OBAKitTests/Networking/CaptivePortalDetectionTests.swift` (the directory exists):

```swift
//
//  CaptivePortalDetectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CFNetwork
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class CaptivePortalDetectionTests: OBATestCase {

    @Test func `CFNetwork ATS error looks like a captive portal`() {
        let service = buildRESTService()
        // Built from the real constant, so this fails if the literal in
        // production code ever stops matching CFNetwork's actual domain.
        let error = NSError(
            domain: kCFErrorDomainCFNetwork as String,
            code: NSURLErrorAppTransportSecurityRequiresSecureConnection
        )
        #expect(service.errorLooksLikeCaptivePortal(error))
    }

    @Test func `JSON parse failure looks like a captive portal`() {
        let service = buildRESTService()
        #expect(service.errorLooksLikeCaptivePortal(NSError(domain: NSCocoaErrorDomain, code: 3840)))
    }

    @Test func `Unrelated error does not look like a captive portal`() {
        let service = buildRESTService()
        #expect(service.errorLooksLikeCaptivePortal(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)) == false)
    }
}
```

- [ ] **Step 2: Run it — all three pass (this is a pin, not a red test)**

Run with `-only-testing:OBAKitTests/CaptivePortalDetectionTests`. Expected: 3 PASS.

- [ ] **Step 3: Replace the symbol**

In `APIService+GetData.swift`, inside `errorLooksLikeCaptivePortal`, replace the second `if`:

```swift
        // The literal value of `kCFErrorDomainCFNetwork`. watchOS has no
        // CFNetwork, so the symbol cannot be named in code that builds there;
        // CaptivePortalDetectionTests pins this string against the real constant.
        if error.domain == "kCFErrorDomainCFNetwork" && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return true
        }
```

If the file has an `import CFNetwork` line, delete it.

- [ ] **Step 4: Run the tests again**

Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Network/APIService/APIService+GetData.swift OBAKitTests
git commit -m "Name the CFNetwork error domain by value; watchOS has no CFNetwork"
```

### Task 3: Split geofencing out of `LocationManager` (seam 1)

**Files:**
- Modify: `OBAKitCore/Location/Location/LocationManagerProtocol.swift:59-72`
- Create: `OBAKitCore/Location/Location/RegionMonitoringLocationManager.swift`
- Create: `OBAKitCore/Location/Location/LocationService+ProximityAlerts.swift`
- Modify: `OBAKitCore/Location/Location/LocationService.swift:44,107,147-157,566-740`
- Modify: `OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift:15`
- Modify: `OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift:15`
- Test: `OBAKitTests/Location/LocationServiceRegionMonitoringTests.swift` (add one test)

**Interfaces:**
- Produces: `public protocol RegionMonitoringLocationManager: LocationManager` with `startMonitoring(for:)`, `stopMonitoring(for:)`, `monitoredRegions`, `maximumRegionMonitoringDistance`. `LocationService.locationManager` and `LocationService.delegates` become internal (`var locationManager: LocationManager`, `let delegates`). Every public proximity API on `LocationService` keeps its exact signature.

watchOS's `CLLocationManager` has no region monitoring. The build error today is `type 'CLLocationManager' does not conform to protocol 'LocationManager'`, plus `cannot override 'locationManager' which has been marked unavailable` on the two delegate callbacks.

- [ ] **Step 1: Write the failing test**

Delegate callbacks declared in a cross-file extension must still register with Objective-C, or Core Location never calls them and every geofence silently dies. Add to `LocationServiceRegionMonitoringTests`:

```swift
    /// The two region callbacks live in `LocationService+ProximityAlerts.swift`.
    /// Core Location finds optional delegate methods by selector, so an
    /// extension that lost its Objective-C entry points would compile, pass
    /// every test that calls the Swift method directly, and never fire.
    @Test func `Region delegate callbacks are visible to Core Location`() {
        let service = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())

        #expect(service.responds(to: #selector(CLLocationManagerDelegate.locationManager(_:didEnterRegion:))))
        #expect(service.responds(to: #selector(CLLocationManagerDelegate.locationManager(_:monitoringDidFailFor:withError:))))
        #expect((LocationManagerMock() as LocationManager) is RegionMonitoringLocationManager)
    }
```

If the suite builds its service differently (look at the top of the file), mirror that construction.

- [ ] **Step 2: Run it to verify it fails to compile**

Run with `-only-testing:OBAKitTests/LocationServiceRegionMonitoringTests`.
Expected: build FAILS with `cannot find type 'RegionMonitoringLocationManager' in scope`.

- [ ] **Step 3: Create the protocol refinement**

Create `OBAKitCore/Location/Location/RegionMonitoringLocationManager.swift`:

```swift
//
//  RegionMonitoringLocationManager.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The part of `CLLocationManager` that arms geofences.
///
/// Split from `LocationManager` because watchOS's `CLLocationManager` has no
/// region monitoring at all: with these four requirements on the base protocol,
/// `CLLocationManager` cannot conform to it there and OBAKitCore does not build
/// for the watch. This file is iOS-only; `LocationManager` is portable.
public protocol RegionMonitoringLocationManager: LocationManager {
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    var monitoredRegions: Set<CLRegion> { get }

    /// The largest radius, in meters, this device will actually monitor.
    ///
    /// An oversize region is not silently clamped: Core Location answers it with
    /// `CLError.regionMonitoringFailure`, delivered asynchronously through
    /// `monitoringDidFailFor` and carrying no radius. Reading the limit up front
    /// is what lets a caller clamp deliberately and report it, rather than learn
    /// later that something failed without learning what.
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
}

extension CLLocationManager: RegionMonitoringLocationManager {
    // nop. CLLocationManager already implements all of the protocol methods.
}
```

In `LocationManagerProtocol.swift`, delete the `// MARK: - Region Monitoring` block — lines 59 through 71, the four requirements and the doc comment — leaving the protocol's closing brace. Nothing else in that file changes.

- [ ] **Step 4: Move the proximity code into an extension**

In `LocationService.swift`:

1. Line 44: `private var locationManager: LocationManager` → `var locationManager: LocationManager`, with this comment above it:

```swift
    // Internal, not private: `LocationService+ProximityAlerts.swift` is a
    // cross-file extension and needs to reach it.
```

2. Line 107: `private let delegates = …` → `let delegates = …` (same reason; no extra comment needed).
3. **Cut** `notifyDelegatesDidEnterMonitoredRegion` and `notifyDelegatesMonitoringDidFail` (lines 147–157).
4. **Cut** everything from `// MARK: - Region Monitoring` (line 566) through the end of `locationManager(_:monitoringDidFailFor:withError:)` (line 740), leaving the class's closing brace.

Create `OBAKitCore/Location/Location/LocationService+ProximityAlerts.swift`. Its body is the cut code, **verbatim, comments included**, wrapped in an extension, with exactly three edits:

```swift
//
//  LocationService+ProximityAlerts.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

// iOS-only: watchOS has no region monitoring. `LocationService` holds no
// proximity *stored* state, which is what lets all of this be an extension.
extension LocationService {

    /// The injected manager, as something that can arm geofences.
    ///
    /// Traps rather than returning nil. On iOS every manager this service is
    /// built with — `CLLocationManager` and both test mocks — conforms, so a
    /// failure here is a new mock that forgot to, and a loud crash in that test
    /// beats a proximity alert that reports `.started` and never fires.
    private var regionMonitor: RegionMonitoringLocationManager {
        guard let monitor = locationManager as? RegionMonitoringLocationManager else {
            preconditionFailure("LocationService needs a RegionMonitoringLocationManager for proximity alerts; got \(type(of: locationManager)).")
        }
        return monitor
    }

    // <the two notifyDelegates… methods, pasted verbatim, still `private`>

    // <everything from `static let proximityRegionPrefix` through
    //  `locationManager(_:monitoringDidFailFor:withError:)`, pasted verbatim>
}
```

The three edits to the pasted code:

- Drop the `// MARK: - Region Monitoring` line's position to the top of the pasted block (keep the mark).
- Replace every `locationManager.monitoredRegions`, `locationManager.maximumRegionMonitoringDistance`, `locationManager.startMonitoring(`, and `locationManager.stopMonitoring(` with `regionMonitor.…`. There are eight: in `monitoredProximityRegions` (1), `startMonitoringProximity` (4), `stopMonitoringProximityAlert` (2), `stopMonitoringAllProximityAlerts` (1). Verify with `grep -c "regionMonitor\." OBAKitCore/Location/Location/LocationService+ProximityAlerts.swift` → `8`.
- Nothing else. `static let` stored properties are legal in extensions; the two `public func locationManager(_:…)` delegate callbacks stay `public`.

Verify nothing proximity-related is left behind: `grep -n "monitoredRegions\|proximityRegion\|didEnterRegion\|monitoringDidFailFor region" OBAKitCore/Location/Location/LocationService.swift` → no output. (`monitoringDidFailFor identifier` in the `LocationServiceDelegate` protocol at the top of the file is expected and stays.)

- [ ] **Step 5: Conform the mocks**

`OBAKitTests/Helpers/Mocks/LocationServiceMocks.swift:15`:

```swift
public class LocationManagerMock: NSObject, RegionMonitoringLocationManager {
```

`OBAKitTests/Helpers/Mocks/MockAuthorizedLocationManager.swift:15`:

```swift
class MockAuthorizedLocationManager: NSObject, RegionMonitoringLocationManager {
```

Both already implement all four members.

- [ ] **Step 6: Run the location suites**

Run `-only-testing:OBAKitTests/LocationServiceRegionMonitoringTests`, then `-only-testing:OBAKitTests/LocationServiceTests`, then `-only-testing:OBAKitTests/ProximityAlertManagerTests`.
Expected: all PASS, including the new test.

- [ ] **Step 7: Commit**

```bash
git add OBAKitCore/Location/Location OBAKitTests/Helpers/Mocks OBAKitTests/Location
git commit -m "Split region monitoring out of LocationManager"
```

### Task 4: Make `ThemeColors` portable (seam 3)

**Files:**
- Create: `OBAKitCore/Theme/ThemeColors.swift`
- Modify: `OBAKitCore/Theme/Theme.swift:41-175` (delete `ThemeColors`)
- Test: `OBAKitTests/Application/ThemeColorsTests.swift` (create)

**Interfaces:**
- Produces: `ThemeColors` with the same 28 public `UIColor` properties, `ThemeColors.shared`, `ThemeColors()`, `ThemeColors(bundle:)`, and — iOS only — `ThemeColors(bundle:traitCollection:)`. New: `ThemeColors.Palette`, with `Palette.watch` (all platforms) and `Palette.system` (not watchOS).

watchOS's `UIColor` has none of the semantic system colors (`.systemRed`, `.label`, `.systemFill`, …), no `init(dynamicProvider:)`, no `UITraitCollection`, and no `init(named:in:compatibleWith:)`. `UIColor(named:)`, `.white`, `.darkGray`, and RGB initializers do exist there. `Formatters` — portable, and needed by the watch — takes a `ThemeColors`.

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Application/ThemeColorsTests.swift`:

```swift
//
//  ThemeColorsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite struct ThemeColorsTests {

    /// The split must not move a single iOS color.
    @Test func `iOS colors are unchanged by the palette split`() {
        let colors = ThemeColors()

        #expect(colors.departureEarly == .systemRed)
        #expect(colors.departureEarlyBackground == .systemRed)
        #expect(colors.departureLate == .systemBlue)
        #expect(colors.departureLateBackground == .systemBlue)
        #expect(colors.departureUnknown == .label)
        #expect(colors.departureUnknownBackground == .systemGray)
        #expect(colors.gray == .systemGray)
        #expect(colors.green == .systemGreen)
        #expect(colors.blue == .systemBlue)
        #expect(colors.groupedTableBackground == .systemGroupedBackground)
        #expect(colors.groupedTableRowBackground == .white)
        #expect(colors.systemBackground == .systemBackground)
        #expect(colors.label == .label)
        #expect(colors.secondaryLabel == .secondaryLabel)
        #expect(colors.separator == .separator)
        #expect(colors.highlightedBackgroundColor == .systemFill)
        #expect(colors.secondaryBackgroundColor == .secondarySystemBackground)
        #expect(colors.propertyChanged == .systemYellow)
        #expect(colors.stopAnnotationFillColor == .systemGray6)
        #expect(colors.stopAnnotationStrokeColor == .darkGray)
        #expect(colors.stopArrowFillColor == .systemRed)
        #expect(colors.systemFill == .systemFill)
        #expect(colors.lightText == .white)
        #expect(colors.errorColor == .systemRed)
    }

    @Test func `On time color is dark green in light mode and system green in dark mode`() {
        let colors = ThemeColors()
        let light = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        #expect(light == UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00))
        #expect(dark == UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(colors.departureOnTimeBackground == colors.departureOnTime)
    }

    @Test func `The trait collection initializer still exists on iOS`() {
        let colors = ThemeColors(bundle: .main, traitCollection: UITraitCollection(userInterfaceStyle: .dark))
        #expect(colors.departureEarly == .systemRed)
    }

    /// The watch face is always dark and its `UIColor` has no dynamic colors,
    /// so every watch value must be fixed: identical under both styles.
    @Test func `Watch palette colors are fixed, not dynamic`() {
        let palette = ThemeColors.Palette.watch
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for color in [palette.red, palette.blue, palette.green, palette.onTime, palette.gray, palette.yellow,
                      palette.label, palette.secondaryLabel, palette.separator, palette.fill,
                      palette.background, palette.secondaryBackground, palette.groupedBackground, palette.gray6] {
            #expect(color.resolvedColor(with: light) == color.resolvedColor(with: dark))
        }
    }

    @Test func `Watch palette is legible on black`() {
        let palette = ThemeColors.Palette.watch
        #expect(palette.label == .white)
        #expect(palette.background == .black)
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run with `-only-testing:OBAKitTests/ThemeColorsTests`.
Expected: build FAILS with `type 'ThemeColors' has no member 'Palette'`.

- [ ] **Step 3: Create `ThemeColors.swift` and empty it out of `Theme.swift`**

Delete lines 41–175 of `OBAKitCore/Theme/Theme.swift` (the `// Every stored property…` comment and the whole `ThemeColors` class). `Theme.swift` keeps `import UIKit` and `ThemeMetrics`, untouched.

Create `OBAKitCore/Theme/ThemeColors.swift`:

```swift
//
//  ThemeColors.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// Every stored property is an immutable UIColor (Sendable); @unchecked only because NSObject is not Sendable.
public final class ThemeColors: NSObject, @unchecked Sendable {

    // <the 28 documented `public let … : UIColor` properties, moved verbatim
    //  from Theme.swift:44-118 — `brand` through `blue`, doc comments included>

    public static let shared = ThemeColors()

    public override convenience init() {
        self.init(bundle: Bundle.main)
    }

    public convenience init(bundle: Bundle) {
        self.init(brand: Palette.brand(in: bundle), palette: .platformDefault)
    }

    #if !os(watchOS)
    // watchOS has neither `UITraitCollection` nor `UIColor(named:in:compatibleWith:)`.
    // This and `Palette.system` below are the only platform conditionals in the
    // theme; keep it that way.
    public convenience init(bundle: Bundle, traitCollection: UITraitCollection?) {
        self.init(brand: UIColor(named: "brand", in: bundle, compatibleWith: traitCollection), palette: .system)
    }
    #endif

    private init(brand: UIColor?, palette: Palette) {
        self.brand = brand ?? UIColor(red: 0.471, green: 0.667, blue: 0.212, alpha: 1.0)  // fallback for swiftui previews

        mapSnapshotOverlayColor = UIColor(white: 0.0, alpha: 0.4)

        departureEarly = palette.red
        departureEarlyBackground = palette.red

        departureOnTime = palette.onTime
        departureOnTimeBackground = palette.onTime

        departureUnknown = palette.label
        departureUnknownBackground = palette.gray

        departureLate = palette.blue
        departureLateBackground = palette.blue

        gray = palette.gray
        green = palette.green
        blue = palette.blue
        groupedTableBackground = palette.groupedBackground
        groupedTableRowBackground = .white
        systemBackground = palette.background
        label = palette.label
        secondaryLabel = palette.secondaryLabel
        separator = palette.separator
        highlightedBackgroundColor = palette.fill
        secondaryBackgroundColor = palette.secondaryBackground
        propertyChanged = palette.yellow

        stopAnnotationFillColor = palette.gray6
        stopAnnotationStrokeColor = .darkGray
        stopArrowFillColor = palette.red
        systemFill = palette.fill
        lightText = .white
        errorColor = palette.red
    }

    /// The system-provided colors the theme is built from.
    ///
    /// iOS uses the semantic, light/dark-adaptive `UIColor`s. watchOS's
    /// `UIColor` has none of them, so the watch gets fixed values — Apple's
    /// published dark-appearance values, since a watch face is always dark.
    struct Palette {
        let red: UIColor
        let blue: UIColor
        let green: UIColor
        let onTime: UIColor
        let gray: UIColor
        let yellow: UIColor
        let label: UIColor
        let secondaryLabel: UIColor
        let separator: UIColor
        let fill: UIColor
        let background: UIColor
        let secondaryBackground: UIColor
        let groupedBackground: UIColor
        let gray6: UIColor

        /// Defined on every platform — not just watchOS — so the iOS-hosted
        /// test suite can check it.
        static let watch = Palette(
            red: UIColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1),
            blue: UIColor(red: 0.039, green: 0.518, blue: 1.000, alpha: 1),
            green: UIColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1),
            onTime: UIColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1),
            gray: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),
            yellow: UIColor(red: 1.000, green: 0.839, blue: 0.039, alpha: 1),
            label: .white,
            secondaryLabel: UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.6),
            separator: UIColor(red: 0.329, green: 0.329, blue: 0.345, alpha: 0.6),
            fill: UIColor(red: 0.471, green: 0.471, blue: 0.502, alpha: 0.36),
            background: .black,
            secondaryBackground: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
            groupedBackground: .black,
            gray6: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
        )

        #if os(watchOS)
        static let platformDefault = watch

        static func brand(in bundle: Bundle) -> UIColor? {
            // watchOS can only look a named color up in the main bundle.
            UIColor(named: "brand")
        }
        #else
        static let platformDefault = system

        static func brand(in bundle: Bundle) -> UIColor? {
            UIColor(named: "brand", in: bundle, compatibleWith: nil)
        }

        static let system = Palette(
            red: .systemRed,
            blue: .systemBlue,
            green: .systemGreen,
            // Hex #007300 (red: 0.00, green: 0.45, blue: 0.00) has a 6.1:1 contrast ratio against white in
            // light mode, clearing the WCAG AA minimum of 4.5:1 for normal-size text.
            // UIColor.systemGreen is better visibility for small text in dark mode.
            // See #506, #508, and #599 for user feedback.
            onTime: UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemGreen
                } else {
                    return UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00)
                }
            },
            gray: .systemGray,
            yellow: .systemYellow,
            label: .label,
            secondaryLabel: .secondaryLabel,
            separator: .separator,
            fill: .systemFill,
            background: .systemBackground,
            secondaryBackground: .secondarySystemBackground,
            groupedBackground: .systemGroupedBackground,
            gray6: .systemGray6
        )
        #endif
    }
}
```

The `#if os(watchOS) … #else … #endif` inside `Palette` and the `#if !os(watchOS)` around the trait-collection initializer are one logical conditional in one file, which is what the spec allows.

If the compiler rejects `static let system` for `Sendable` reasons under Swift 6 (`UIColor` is `Sendable`, so it should not), mark `Palette` as `struct Palette: @unchecked Sendable` with the comment "every member is an immutable UIColor".

- [ ] **Step 4: Run the tests**

Run `-only-testing:OBAKitTests/ThemeColorsTests`, then `-only-testing:OBAKitTests/FormattersTests`.
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Theme OBAKitTests/Application/ThemeColorsTests.swift
git commit -m "Split ThemeColors into a portable file with a fixed watch palette"
```

### Task 5: Fence the Live Activity properties (seam 2) and lift the polyline fence (seam 5)

**Files:**
- Modify: `OBAKitCore/Orchestration/CoreApplication.swift:216-232`
- Modify: `OBAKitCore/Models/Helpers/Polyline.swift:60-68`

**Interfaces:**
- Produces: no API change on iOS. On watchOS, `CoreApplication` has no `liveActivityRegistry` / `liveActivityTracker`, and `Polyline.mkPolyline` exists.

Both are two-line edits with no iOS-observable behavior, so they share a task. Neither can be unit-tested from an iOS-hosted target: the proof is the watchOS build in Task 8. The existing suites are the regression check.

- [ ] **Step 1: Fence the two lazy properties**

They are *stored* lazy properties, so they cannot move to an extension in the iOS tree; a conditional is the only option. In `CoreApplication.swift`, wrap from the `// MARK: - Live Activities` line through the end of the `liveActivityTracker` declaration:

```swift
    // ActivityKit is iOS/iPadOS only, and `import ActivityKit` fails watchOS
    // dependency scanning outright, so `LiveActivityRegistry` and
    // `LiveActivityTracker` are not compiled for the watch. These are stored
    // lazy properties and cannot move to an extension — hence the one
    // conditional this file carries.
    #if canImport(ActivityKit)
    // MARK: - Live Activities

    /// Owns the Live Activity push subscriptions registered with OBACloud: …
    public private(set) lazy var liveActivityRegistry = LiveActivityRegistry(
        userDefaults: userDefaults,
        obacoServiceProvider: { [weak self] in self?.obacoService }
    )

    /// Owns the ActivityKit observers that feed `liveActivityRegistry`. …
    public private(set) lazy var liveActivityTracker = LiveActivityTracker(registry: liveActivityRegistry)
    #endif
```

Keep both existing doc comments in full; they are abbreviated above only to show placement.

- [ ] **Step 2: Lift the polyline fence**

`MKPolyline` is available on watchOS; this was checked by type-checking `MKPolyline(coordinates:count:)` and `boundingMapRect` against the watchOS device SDK for `arm64_32` at the 11.0 target. In `OBAKitCore/Models/Helpers/Polyline.swift`, delete the `#if !os(watchOS)` line above `mkPolyline` and its matching `#endif`, leaving:

```swift
    /// Convert polyline to MKPolyline to use with MapKit (nil if polyline cannot be decoded)
    @available(tvOS 9.2, *)
    public var mkPolyline: MKPolyline? {
        guard let coordinates = self.coordinates else { return nil }
        let mkPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        return mkPolyline
    }
```

If the top of that file wraps `import MapKit` in the same kind of fence, lift that too.

- [ ] **Step 3: Run the affected suites**

Run `-only-testing:OBAKitTests/PolylineTests` and `-only-testing:OBAKitTests/ShapeModelOperationTests`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add OBAKitCore/Orchestration/CoreApplication.swift OBAKitCore/Models/Helpers/Polyline.swift
git commit -m "Fence Live Activity state behind canImport(ActivityKit); unfence mkPolyline"
```

### Task 6: PR 1 gate

- [ ] **Step 1: Full unit suite**

Run the standard command with `-only-testing:OBAKitTests`.
Expected: PASS. `SearchViewModelTests` (concurrency guard) and `StopSheetPresenterTests` (dismissal) are known flakes — re-run once before investigating either.

- [ ] **Step 2: Lint**

Run: `swiftlint lint --quiet; echo "exit: $?"`
Expected: no errors.

- [ ] **Step 3: Open the PR**

Title: `watchOS step 1: make OBAKitCore's watch-hostile seams portable`. Body: link the spec; list the six seams; state "No iOS behavior change. No directory moves — the three new iOS-only files are relocated in step 2."

---
# PR 2 — The second directory and the watchOS destination

Branch: `watchos/step-2-two-destinations` from `main`, after PR 1 merges.

This is the PR where the spec expects surprises: a second layer of watchOS compile errors the first pass masked, and any further 32-bit overflows. Task 8 is a triage procedure rather than a script for that reason.

### Task 7: Create `OBAKitCoreiOS/` and move the iOS-only files

**Files:**
- Create: `OBAKitCoreiOS/UIKit/`, `OBAKitCoreiOS/LiveActivities/`, `OBAKitCoreiOS/Location/`
- Move: 23 files (listed below)
- Modify: `OBAKitCore/project.yml`
- Modify: `scripts/extract_strings`
- Modify: `.swiftlint.yml`

**Interfaces:**
- Produces: an `OBAKitCore` target that still builds for iOS only, from two directories. Module name, public API, and every `import` are unchanged.

This task deliberately does **not** add the watchOS destination. It proves the sibling-directory mechanism on iOS at full scale first, so a failure here is unambiguous.

- [ ] **Step 1: Establish a strings baseline before anything moves**

`en.lproj` drifts from source between regenerations, so a post-move diff is meaningless without this.

```bash
scripts/extract_strings
git status --short OBAKitCore/Strings OBAKit/Strings
```

If that produces a diff, commit it on its own **first** (`git commit -am "Regenerate en.lproj strings"`), so the move's diff can be read against a clean baseline.

- [ ] **Step 2: Move the files with `git mv`**

```bash
mkdir -p OBAKitCoreiOS/UIKit OBAKitCoreiOS/LiveActivities OBAKitCoreiOS/Location

# UIKit view code (11)
git mv OBAKitCore/Extensions/UIKitExtensions.swift        OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Extensions/AutoLayoutExtensions.swift   OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Collections/EmptyDataSetView.swift      OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Collections/ActivityIndicatedButton.swift OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Collections/ListKitExtensions.swift     OBAKitCoreiOS/UIKit/
git mv OBAKitCore/UI/DepartureTimeBadge.swift             OBAKitCoreiOS/UIKit/
git mv OBAKitCore/UI/ProminentButton.swift                OBAKitCoreiOS/UIKit/
git mv OBAKitCore/UI/PaddingLabel.swift                   OBAKitCoreiOS/UIKit/
git mv OBAKitCore/UI/ArrivalDepartureDrivenUI.swift       OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Utilities/UIViewPreview.swift           OBAKitCoreiOS/UIKit/
git mv OBAKitCore/Utilities/ImageBadgeRenderer.swift      OBAKitCoreiOS/UIKit/

# Everything that imports or renders ActivityKit (10)
git mv OBAKitCore/LiveActivities/LiveActivityLookup.swift          OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/LiveActivityRegistry.swift        OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/LiveActivityShortcutRequest.swift OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/LiveActivityStaleChrome.swift     OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/LiveActivityTracker.swift         OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/LiveActivityUpdateCoalescer.swift OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/LiveActivities/TripLiveActivityRelevance.swift   OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/Models/TripAttributes.swift                      OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/UI/TripActivityPresenter.swift                   OBAKitCoreiOS/LiveActivities/
git mv OBAKitCore/UI/TripLiveActivityCardView.swift                OBAKitCoreiOS/LiveActivities/

# The two files Task 3 created (2)
git mv OBAKitCore/Location/Location/RegionMonitoringLocationManager.swift   OBAKitCoreiOS/Location/
git mv OBAKitCore/Location/Location/LocationService+ProximityAlerts.swift   OBAKitCoreiOS/Location/

rmdir OBAKitCore/LiveActivities
```

`OBAKitCore/Collections/` may now be empty; if `ls OBAKitCore/Collections` prints nothing, `rmdir` it. `Theme.swift` stays (see "Deviations", item 2).

- [ ] **Step 3: Add the second source to `OBAKitCore/project.yml`**

Replace the `sources:` block:

```yaml
    sources:
      # XcodeGen's synced folders can't mark headers public, so the umbrella
      # header is carved out of the buildable folder and added as an explicit
      # public header.
      - path: "."
        # The .proto schema is source material for pre-generated Swift, not a
        # target member; without the exclusion Xcode tries to compile it.
        # project.yml is excluded so it stops shipping as a bundle resource.
        excludes: ["OBAKitCore.h", "Models/Protobuf/gtfs-realtime.proto", "project.yml"]
      - path: OBAKitCore.h
        headerVisibility: public
      # iOS-only half of the same module. It MUST be a sibling directory with
      # `type: group`: XcodeGen 2.46 silently ignores destinationFilters on a
      # synced folder, and a group nested inside the synced root dangles its
      # file reference and breaks the iOS build. Because it is a group, not a
      # synced folder, files added here need `scripts/generate_project`.
      - path: ../OBAKitCoreiOS
        type: group
        destinationFilters: [iOS]
```

Leave `platform: iOS` in place for this task.

- [ ] **Step 4: Point the tooling at both directories**

`scripts/extract_strings`, first line:

```bash
find OBAKitCore OBAKitCoreiOS -name "*.swift" -print0 | xargs -0 genstrings -s OBALoc -o OBAKitCore/Strings/en.lproj
```

`.swiftlint.yml`, `included:`:

```yaml
included: # paths to include during linting. `--path` is ignored if present.
  - OBAKit
  - OBAKitCore
  - OBAKitCoreiOS
  - OBAWidget
```

and widen the comment on `hardcoded_app_name` from "OBAKit/OBAKitCore/OBAWidget" to "OBAKit/OBAKitCore/OBAKitCoreiOS/OBAWidget".

- [ ] **Step 5: Verify the generated project filters every moved file**

```bash
scripts/generate_project OneBusAway
echo "platformFilters entries: $(grep -c 'platformFilters = (ios, );' OBAKit.xcodeproj/project.pbxproj)"
echo "dangling TEMP refs:      $(grep -c 'TEMP_' OBAKit.xcodeproj/project.pbxproj)"
```

Expected: at least 23 `platformFilters` entries (one per moved file's build-file record), and **0** `TEMP_` references. A nonzero `TEMP_` count means the group was nested or mis-pathed; fix the YAML before building.

- [ ] **Step 6: Verify strings and lint**

```bash
scripts/extract_strings && git diff --stat OBAKitCore/Strings OBAKit/Strings
swiftlint lint --quiet; echo "lint exit: $?"
```

Expected: **empty** strings diff (the one string at risk is in `LiveActivityStaleChrome.swift`; an empty diff proves it survived), and no lint errors.

- [ ] **Step 7: Full iOS suite**

Run the standard command with `-only-testing:OBAKitTests`. Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A OBAKitCore OBAKitCoreiOS scripts/extract_strings .swiftlint.yml
git commit -m "Move OBAKitCore's iOS-only files to a sibling OBAKitCoreiOS directory"
```

### Task 8: Add the watchOS destination and get a clean device-architecture build

**Files:**
- Modify: `OBAKitCore/project.yml`
- Modify: whatever the second layer of errors names (procedure below)

**Interfaces:**
- Produces: `xcodebuild build -scheme OBAKitCore -destination 'generic/platform=watchOS'` exits 0 for `arm64` **and** `arm64_32`.

- [ ] **Step 1: Turn on the second destination**

In `OBAKitCore/project.yml` replace `platform: iOS` with:

```yaml
    supportedDestinations: [iOS, watchOS]
```

and add to `settings.base`:

```yaml
        # A per-target `deploymentTarget: {iOS: …, watchOS: …}` map is silently
        # dropped on a supportedDestinations target; watchOS would fall to the
        # SDK default and dependents fail with "minimum deployment target of
        # watchOS 27.0". 11.0 is the release paired with the iOS 18.0 floor.
        WATCHOS_DEPLOYMENT_TARGET: "11.0"
```

- [ ] **Step 2: Confirm the settings took**

```bash
scripts/generate_project OneBusAway
xcodebuild -project OBAKit.xcodeproj -scheme OBAKitCore -showBuildSettings \
  -destination 'generic/platform=watchOS' 2>/dev/null \
  | grep -E "^\s+(WATCHOS_DEPLOYMENT_TARGET|ARCHS|SDKROOT|SUPPORTED_PLATFORMS) ="
```

Expected: `WATCHOS_DEPLOYMENT_TARGET = 11.0` and `ARCHS = arm64 arm64_32`. If the deployment target reads `27.0`, the setting did not land; do not proceed.

- [ ] **Step 3: Confirm iOS is unharmed before touching anything else**

Run the standard command with `-only-testing:OBAKitTests/EpochWidthTests` (a fast canary that forces a full iOS build). Expected: PASS.

- [ ] **Step 4: Build for watchOS device architectures**

Run the "Build OBAKitCore for watchOS device architectures" command from the header. Save the full log too:

```bash
set -o pipefail
xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO \
  > /tmp/obakitcore-watchos.log 2>&1; echo "exit: $?"
grep -E "error:" /tmp/obakitcore-watchos.log | sed -E 's#^.*/(OBAKitCore(iOS)?/)#\1#' | sort -u
```

If it exits 0, skip to Step 6.

- [ ] **Step 5: Triage the second layer**

Work the unique error list top to bottom. For each error, apply the **first** rule that matches, rebuild, and re-list. Do not batch fixes blind; one fix often clears a dozen downstream errors.

| The error says | It means | Do this |
|---|---|---|
| `Clang dependency scanning failure`, or exactly one error naming `ActivityKit` | A file that imports ActivityKit is still in the portable tree. The module never compiled; the rest of the list is fiction. | `grep -rln "import ActivityKit" OBAKitCore` and `git mv` each hit to `OBAKitCoreiOS/LiveActivities/`. |
| `integer literal '…' overflows when stored into 'Int'` | A 32-bit overflow the grep audit missed. | Type the value `Int64` (or decode as `Date`). Add a line to `EpochWidthTests` pinning the declared type. |
| `'X' is unavailable in watchOS`, in a file that is **all** UIKit view code | The file belongs in the iOS tree. | `git mv` it to `OBAKitCoreiOS/UIKit/`. |
| `'X' is unavailable in watchOS`, in a file the watch **needs** (models, services, formatters, networking, SwiftUI views) | A new seam. | Move only the offending members to a new `<Type>+iOS.swift` extension under `OBAKitCoreiOS/`. If they are stored properties, stop and escalate: that needs a third conditional, which the Global Constraints forbid without the maintainer's sign-off. |
| `cannot find 'X' in scope`, where `X` was moved to the iOS tree | A portable file depends on an iOS-only one. | If the *caller* is iOS-only in spirit, move the caller. If not, move the smallest portable piece of `X` back (as was done for `ThemeColors`). Never resolve this with a new `#if`. |
| `cannot find 'X' in scope`, where `X` is an Apple symbol | A framework watchOS lacks. | Check availability with `sosumi`/Apple docs. If there is a value-equivalent (as with `kCFErrorDomainCFNetwork`), use it and pin it with a test; otherwise treat as a new seam (row 4). |
| An error inside `.build/checkouts` (GRDB, SwiftProtobuf) | Unexpected: both were built for `arm64_32` during spec validation. | Stop and escalate with the log. |

After every file move: `scripts/generate_project OneBusAway`, then rebuild **both** platforms (Step 3's canary, then Step 4). Record each second-layer fix in the PR description; the follow-on plans need that list.

- [ ] **Step 6: Prove the guardrail catches what it exists to catch**

Two negative checks, each reverted immediately:

```bash
# (a) 32-bit overflow: simulator green, device red.
printf '\nlet _watchProbe: Int = 10_000_000_000\n' >> OBAKitCore/Models/REST/RESTAPIResponse.swift
xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "overflows|BUILD"
git checkout OBAKitCore/Models/REST/RESTAPIResponse.swift
```

Expected: `integer literal '10000000000' overflows when stored into 'Int'` and `BUILD FAILED`.

```bash
# (b) UIKit view code in the portable tree.
printf 'import UIKit\nfinal class WatchProbeView: UIView {}\n' > OBAKitCore/UI/WatchProbeView.swift
xcodebuild build -project OBAKit.xcodeproj -scheme OBAKitCore \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "unavailable in watchOS|BUILD"
rm OBAKitCore/UI/WatchProbeView.swift
```

Expected: `'UIView' is unavailable in watchOS` and `BUILD FAILED`. (`OBAKitCore/` is a synced folder, so the probe file needs no project regeneration.) Finish with `git status --short` → clean apart from intended changes.

- [ ] **Step 7: Verify iOS-only symbols stayed out of the watch binary**

```bash
WATCH_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Debug-watchos/OBAKitCore.framework/OBAKitCore" -newer OBAKitCore/project.yml | head -1)
lipo -archs "$WATCH_BIN"
nm -gU "$WATCH_BIN" 2>/dev/null | grep -c "LiveActivityRegistry\|EmptyDataSetView"
```

Expected: `arm64 arm64_32` (order may vary), and a count of `0`.

- [ ] **Step 8: Full iOS suite, then commit**

Run `-only-testing:OBAKitTests`. Expected: PASS.

```bash
git add -A OBAKitCore OBAKitCoreiOS OBAKitTests
git commit -m "Build OBAKitCore for watchOS alongside iOS"
```

### Task 9: The permanent device-architecture CI step, and the contributor docs

**Files:**
- Modify: `.github/workflows/tests.yml` (after the `Concurrency warning ratchet` step, before `OBAKit Unit Test`)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the CI step**

Insert into the `build` job:

```yaml
    # watchOS device-architecture compile (docs/superpowers/specs/2026-09-20-watchos-architecture-design.md, §5).
    # Permanent, and deliberately a DEVICE build: `Int` is 32 bits on arm64_32
    # Apple Watches, watch simulators on Apple silicon are 64-bit, and an
    # overflowing literal builds green for the simulator and red here. This is
    # the only check in the repo that compiles for a 32-bit Int. It also stops a
    # UIView landing in the portable OBAKitCore/ tree on green iOS CI.
    # The iOS App build never replaces it: that compiles simulator slices only.
    - name: Check watchOS SDK
      run: |
        if xcodebuild -showsdks | grep -q "watchos"; then
          echo "watchOS device SDK present:"; xcodebuild -showsdks | grep -i watch
        else
          echo "No watchOS SDK on this image; downloading…"
          xcodebuild -downloadPlatform watchOS
        fi

    - name: Build OBAKitCore for watchOS (arm64 + arm64_32)
      timeout-minutes: 20
      run: |
        set -o pipefail
        xcodebuild build \
          -project 'OBAKit.xcodeproj' \
          -scheme 'OBAKitCore' \
          -destination 'generic/platform=watchOS' \
          -derivedDataPath DerivedData \
          CODE_SIGNING_ALLOWED=NO \
          -quiet \
          | tee xcodebuild-watchos.log
```

A device build needs no simulator runtime, so there is no `simctl` guard. The scheme switches from `OBAKitCore` to `WatchApp` in the step-5 plan.

- [ ] **Step 2: Document the rule for contributors**

In `CLAUDE.md`, under `## Architecture` → `### Framework Structure`, replace the OBAKitCore bullet with:

```markdown
- **OBAKitCore**: Core business logic, networking, data models (application extension safe). One module, two directories:
  - `OBAKitCore/` — portable. Builds for **iOS and watchOS**. No UIKit view code, no ActivityKit, no region monitoring.
  - `OBAKitCoreiOS/` — iOS-only files of the *same module* (no separate `import`). UIKit views, Live Activities, geofencing. It is an XcodeGen `group`, so run `scripts/generate_project` after adding a file here.
```

and under `## Development Notes` add:

```markdown
- **`Int` is 32 bits on most Apple Watches** (`arm64_32`), and watch simulators hide it. In `OBAKitCore/`, never decode an epoch value as `Int` — use `Int64` or `Date`. Check with `xcodebuild build -scheme OBAKitCore -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO`; CI runs the same build.
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tests.yml CLAUDE.md
git commit -m "CI: compile OBAKitCore for watchOS device architectures"
```

- [ ] **Step 4: Push and read the CI timings**

Push the branch, open the PR (title: `watchOS step 2: OBAKitCore builds for watchOS`), and record the wall time of `Build OBAKitCore for watchOS` in the PR description — the spec lists it as unmeasured. Gate on the named `build` job's conclusion, not on `gh pr checks` exiting 0 (a PR whose build job never ran reads green).

---

# PR 3 — Stateless arrivals, a persisted region, and the iOS widget

Branch: `watchos/step-3-stateless-arrivals` from `main`, after PR 2 merges. Everything new in OBAKitCore here must build for watchOS: after each core task, run the device-architecture build from the header.

### Task 10: `UserUUID` — the client identifier without a `CoreApplication`

**Files:**
- Create: `OBAKitCore/Orchestration/UserUUID.swift`
- Modify: `OBAKitCore/Orchestration/CoreApplication.swift:246-261,291-293`
- Test: `OBAKitTests/Application/UserUUIDTests.swift` (create)

**Interfaces:**
- Produces: `public enum UserUUID { public static let defaultsKey: String; public static func value(in userDefaults: UserDefaults) -> String }`. `CoreApplication.userUUID` keeps its signature and delegates to it.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  UserUUIDTests.swift
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
final class UserUUIDTests: OBATestCase {

    @Test func `Creates a UUID once and returns the same one afterwards`() {
        let first = UserUUID.value(in: userDefaults)
        let second = UserUUID.value(in: userDefaults)

        #expect(UUID(uuidString: first) != nil)
        #expect(first == second)
    }

    @Test func `Reads an identifier an earlier version already stored`() {
        userDefaults.set("existing-id", forKey: "userUUIDDefaultsKey")
        #expect(UserUUID.value(in: userDefaults) == "existing-id")
    }

    /// A widget reading the app-group suite must get the app's identifier,
    /// not mint a second one.
    @Test @MainActor func `Matches what CoreApplication reports for the same suite`() {
        let queue = OperationQueue()
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        #expect(UserUUID.value(in: userDefaults) == application.userUUID)
        queue.cancelAllOperations()
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile** — `cannot find 'UserUUID' in scope`.

- [ ] **Step 3: Implement**

Create `OBAKitCore/Orchestration/UserUUID.swift`:

```swift
//
//  UserUUID.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A unique (but not personally-identifying) identifier for the current user,
/// used to correlate crash logs and API requests to a single install.
///
/// A free-standing helper rather than a `CoreApplication` property so that a
/// widget extension can identify itself to the REST API without constructing a
/// `CoreApplication` — which starts a regions fetch, opens the stop cache, and
/// bumps the launch counter. Pass the app-group suite and the extension shares
/// the app's identifier.
public enum UserUUID {
    public static let defaultsKey = "userUUIDDefaultsKey"

    public static func value(in userDefaults: UserDefaults) -> String {
        if let uuid = userDefaults.object(forKey: defaultsKey) as? String {
            return uuid
        }

        let uuid = UUID().uuidString
        userDefaults.set(uuid, forKey: defaultsKey)
        return uuid
    }
}
```

In `CoreApplication.swift`, delete `private let userUUIDDefaultsKey = "userUUIDDefaultsKey"` and replace the `userUUID` body and the `migrate(userID:)` body:

```swift
    /// A unique (but not personally-identifying) identifier for the current user that is used
    /// to correlate crash logs and other events to a single person.
    @objc public var userUUID: String {
        UserUUID.value(in: userDefaults)
    }
```

```swift
    public func migrate(userID: String) {
        userDefaults.set(userID, forKey: UserUUID.defaultsKey)
    }
```

- [ ] **Step 4: Run** `-only-testing:OBAKitTests/UserUUIDTests`. Expected: PASS. Then the watchOS device build. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Orchestration OBAKitTests/Application/UserUUIDTests.swift
git commit -m "Extract UserUUID so extensions can identify themselves without CoreApplication"
```

### Task 11: Persist the resolved `Region` to the app-group suite

**Files:**
- Create: `OBAKitCore/Location/Regions/ResolvedRegionStore.swift`
- Create: `OBAKitCore/Location/Regions/ResolvedRegionPersister.swift`
- Modify: `OBAKitCore/Location/Regions/RegionsService.swift:16-28,251-273`
- Modify: `OBAKit/Orchestration/Application.swift` (init, after `super.init(config:)`)
- Test: `OBAKitTests/Location/ResolvedRegionStoreTests.swift` (create)

**Interfaces:**
- Produces:
  - `public struct ResolvedRegionStore { public static let defaultsKey: String; public init(userDefaults: UserDefaults); public func write(_ region: Region?); public func region(bundledRegionsFilePath: String?) -> Region? }`
  - `@MainActor public final class ResolvedRegionPersister: NSObject, RegionsServiceDelegate { public init(regionsService: RegionsService, store: ResolvedRegionStore); public func persist() }`
  - New optional delegate method: `regionsService(_ service: RegionsService, updatedCustomRegions regions: [Region])`.

**Why this exists.** `RegionsService.currentRegion` stores only an identifier and resolves it against `regions + customRegions`. Custom regions are files under the *process's* Documents directory, and a widget extension has its own sandbox — so a widget resolves a custom region to `nil` and renders nothing. This is a live bug in the iOS widget today.

**Why a delegate object and not code inside `RegionsService`.** A widget that falls back to building a `RegionsService` would then *write*, and for a custom region it would write `nil` — erasing the app's good value. Only a process that owns the truth may write. The app owns a persister; extensions never do.

**The four write triggers**, and why `updatedRegion` alone is not enough: the `currentRegion` setter returns early when the identifier is unchanged (`RegionsService.swift:207-208`), so a server-side change to the *current* region (a new base URL) fires only `updatedRegionsList`.

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Location/ResolvedRegionStoreTests.swift`:

```swift
//
//  ResolvedRegionStoreTests.swift
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
final class ResolvedRegionStoreTests: OBATestCase {

    @MainActor
    private func makeRegionsService(fileStorage: MockRegionsFileStorage) -> RegionsService {
        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        return RegionsService(
            apiService: nil,
            locationService: locationService,
            userDefaults: userDefaults,
            bundledRegionsFilePath: bundledRegionsPath,
            apiPath: nil,
            fileStorage: fileStorage
        )
    }

    // MARK: - Store

    @Test func `Round trips a custom region, base URL included`() throws {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let custom = Fixtures.customRegionWithSidecarAndUmami

        store.write(custom)
        let restored = try #require(store.region(bundledRegionsFilePath: nil))

        #expect(restored.regionIdentifier == custom.regionIdentifier)
        #expect(restored.OBABaseURL == custom.OBABaseURL)
        #expect(restored.name == custom.name)
    }

    @Test func `Writing nil clears the key`() {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(Fixtures.pugetSoundRegion)
        store.write(nil)

        #expect(userDefaults.object(forKey: ResolvedRegionStore.defaultsKey) == nil)
        #expect(store.region(bundledRegionsFilePath: nil) == nil)
    }

    /// The first widget reload after this ships happens before the app has
    /// launched and written anything.
    @Test func `Falls back to identifier lookup in the bundled regions when the key is absent`() throws {
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        let region = try #require(store.region(bundledRegionsFilePath: bundledRegionsPath))
        #expect(region.regionIdentifier == pugetSoundRegionIdentifier)
    }

    @Test func `Fallback returns nil for an identifier the bundle does not know`() {
        userDefaults.set(987_654, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        #expect(store.region(bundledRegionsFilePath: bundledRegionsPath) == nil)
    }

    @Test func `A corrupt stored value falls back instead of crashing`() throws {
        userDefaults.set(Data("not a plist".utf8), forKey: ResolvedRegionStore.defaultsKey)
        userDefaults.set(pugetSoundRegionIdentifier, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)

        let region = try #require(store.region(bundledRegionsFilePath: bundledRegionsPath))
        #expect(region.regionIdentifier == pugetSoundRegionIdentifier)
    }

    // MARK: - Persister: the four triggers

    @Test @MainActor func `Trigger 1, launch: writes the current region on init`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        service.currentRegion = try #require(service.find(id: pugetSoundRegionIdentifier))
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(nil)

        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == pugetSoundRegionIdentifier)
        withExtendedLifetime(persister) {}
    }

    @Test @MainActor func `Trigger 2, updatedRegion: writes when the current region changes`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        let other = try #require(service.regions.first { $0.regionIdentifier != service.currentRegion?.regionIdentifier })
        service.currentRegion = other

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == other.regionIdentifier)
        withExtendedLifetime(persister) {}
    }

    /// The setter early-returns on an unchanged identifier, so a server-side
    /// edit to the current region arrives only as a list update.
    @Test @MainActor func `Trigger 3, updatedRegionsList: rewrites even though the identifier is unchanged`() throws {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        service.currentRegion = try #require(service.find(id: pugetSoundRegionIdentifier))
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        store.write(nil)
        persister.regionsService(service, updatedRegionsList: service.regions)

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == pugetSoundRegionIdentifier)
    }

    @Test @MainActor func `Trigger 4, custom regions: editing the current custom region rewrites it`() async throws {
        let fileStorage = MockRegionsFileStorage()
        let service = makeRegionsService(fileStorage: fileStorage)
        let custom = Fixtures.customRegionWithSidecarAndUmami
        try await service.add(customRegion: custom)
        service.currentRegion = custom

        let store = ResolvedRegionStore(userDefaults: userDefaults)
        let persister = ResolvedRegionPersister(regionsService: service, store: store)
        store.write(nil)

        try await service.add(customRegion: custom)   // an edit: same identifier, replaces

        #expect(store.region(bundledRegionsFilePath: nil)?.regionIdentifier == custom.regionIdentifier)
        withExtendedLifetime(persister) {}
    }

    @Test @MainActor func `Clears the key when there is no current region`() {
        let service = makeRegionsService(fileStorage: MockRegionsFileStorage())
        userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        store.write(Fixtures.pugetSoundRegion)

        let persister = ResolvedRegionPersister(regionsService: service, store: store)

        #expect(userDefaults.object(forKey: ResolvedRegionStore.defaultsKey) == nil)
        withExtendedLifetime(persister) {}
    }
}
```

`MockRegionsFileStorage.saveCustomRegion` replaces by identifier and appends, so the "edit" in the custom-region test is a real replace.

- [ ] **Step 2: Run to verify it fails to compile** — `cannot find 'ResolvedRegionStore' in scope`.

- [ ] **Step 3: Implement the store**

Create `OBAKitCore/Location/Regions/ResolvedRegionStore.swift`:

```swift
//
//  ResolvedRegionStore.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The app's current `Region`, stored whole in a `UserDefaults` suite.
///
/// `RegionsService` deliberately persists only the region's *identifier* and
/// resolves it on read. That is right inside one process and wrong across two:
/// custom regions live in the app's own Documents directory, which a widget
/// extension cannot see, so the extension resolves the identifier to nothing.
/// The app writes the resolved region here (see `ResolvedRegionPersister`);
/// extensions read it and never write.
public struct ResolvedRegionStore {
    public static let defaultsKey = "OBAResolvedCurrentRegion"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// Stores `region`, or clears the stored value when it is nil.
    public func write(_ region: Region?) {
        guard let region else {
            userDefaults.removeObject(forKey: Self.defaultsKey)
            return
        }

        do {
            userDefaults.set(try PropertyListEncoder().encode(region), forKey: Self.defaultsKey)
        } catch {
            Logger.error("ResolvedRegionStore: failed to encode region \(region.regionIdentifier): \(error)")
        }
    }

    /// The stored region. When nothing usable is stored — the app has not
    /// launched since this shipped, or the value is corrupt — falls back to
    /// looking the stored *identifier* up in the bundled regions file, which
    /// covers every region except a custom one.
    public func region(bundledRegionsFilePath: String?) -> Region? {
        if let data = userDefaults.data(forKey: Self.defaultsKey) {
            do {
                return try PropertyListDecoder().decode(Region.self, from: data)
            } catch {
                Logger.error("ResolvedRegionStore: stored region is unreadable, falling back: \(error)")
            }
        }

        guard
            let identifier = userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int,
            let path = bundledRegionsFilePath,
            let data = FileManager.default.contents(atPath: path),
            let response = try? JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[Region]>.self, from: data)
        else {
            return nil
        }

        return response.list.first { $0.regionIdentifier == identifier }
    }
}
```

- [ ] **Step 4: Implement the delegate callback and the persister**

In `RegionsService.swift`, add to `RegionsServiceDelegate` after `updatedRegion`:

```swift
    /// A custom region was added, replaced, or deleted. `updatedRegion` does not
    /// cover this: editing the *current* custom region keeps its identifier, so
    /// the `currentRegion` setter never fires.
    @objc optional func regionsService(_ service: RegionsService, updatedCustomRegions regions: [Region])
```

Add next to the other `notifyDelegates…` helpers:

```swift
    private func notifyDelegatesCustomRegionsUpdated() {
        let customRegions = self.customRegions
        for delegate in delegates.allObjects {
            delegate.regionsService?(self, updatedCustomRegions: customRegions)
        }
    }
```

and call `notifyDelegatesCustomRegionsUpdated()` as the last line of both `add(customRegion:)` and `delete(customRegionIdentifier:)` — after the `customRegionsCache = nil` line, so the delegate reads fresh data.

Create `OBAKitCore/Location/Regions/ResolvedRegionPersister.swift`:

```swift
//
//  ResolvedRegionPersister.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Keeps `ResolvedRegionStore` in step with `RegionsService.currentRegion`.
///
/// Owned by the *app* only. An extension must never create one: its
/// `RegionsService` cannot see custom regions, so it would overwrite the app's
/// correct value with nil.
///
/// Writes on four triggers — launch (init), `updatedRegion`,
/// `updatedRegionsList`, and `updatedCustomRegions`. All four are needed: the
/// `currentRegion` setter returns early on an unchanged identifier, so a
/// server-side edit to the current region arrives only as a list update, and an
/// edit to the current custom region only as a custom-regions update.
@MainActor
public final class ResolvedRegionPersister: NSObject, RegionsServiceDelegate {
    private weak var regionsService: RegionsService?
    private let store: ResolvedRegionStore

    public init(regionsService: RegionsService, store: ResolvedRegionStore) {
        self.regionsService = regionsService
        self.store = store
        super.init()

        // `RegionsService` holds its delegates weakly; the owner retains us.
        regionsService.addDelegate(self)
        persist()
    }

    /// Writes the current region, or clears the store when there is none.
    public func persist() {
        store.write(regionsService?.currentRegion)
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        persist()
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        persist()
    }

    public func regionsService(_ service: RegionsService, updatedCustomRegions regions: [Region]) {
        persist()
    }
}
```

- [ ] **Step 5: Have the app own one**

In `OBAKit/Orchestration/Application.swift`, add a stored property near `bookmarkWidgetRefresher`:

```swift
    /// Mirrors the resolved current region into the app-group suite so the
    /// widget extension — which cannot see this process's custom regions — can
    /// read it. Retained here because `RegionsService` holds delegates weakly.
    private var resolvedRegionPersister: ResolvedRegionPersister?
```

and in `init(config:)`, immediately after `super.init(config: config)`:

```swift
        resolvedRegionPersister = ResolvedRegionPersister(
            regionsService: regionsService,
            store: ResolvedRegionStore(userDefaults: userDefaults)
        )
```

- [ ] **Step 6: Run** `-only-testing:OBAKitTests/ResolvedRegionStoreTests`, then `-only-testing:OBAKitTests/RegionsServiceTests`. Expected: PASS. Then the watchOS device build. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add OBAKitCore/Location/Regions OBAKit/Orchestration/Application.swift OBAKitTests
git commit -m "Persist the resolved region to the app-group suite for extensions"
```

### Task 12: `BookmarkArrivalsLoader` — stateless, streaming, deduped by stop

**Files:**
- Create: `OBAKitCore/Bookmarks/BookmarkArrivalsLoader.swift`
- Modify: `OBAKitCore/Bookmarks/TripBookmarkKey.swift:13`
- Test: `OBAKitTests/Bookmarks/BookmarkArrivalsLoaderTests.swift` (create)

**Interfaces:**
- Produces:

```swift
public struct BookmarkArrivalsRequest: Hashable, Sendable {
    public let stopID: StopID
    public let tripKey: TripBookmarkKey?
    public init(stopID: StopID, tripKey: TripBookmarkKey? = nil)
    public init(bookmark: Bookmark)
    public func matching(_ arrivals: [ArrivalDeparture]) -> [ArrivalDeparture]
}

public struct BookmarkArrivalsLoader: Sendable {
    public init(minutesBefore: UInt = 0, minutesAfter: UInt = 60)
    public func arrivals(for requests: [BookmarkArrivalsRequest], using apiService: RESTAPIService)
        -> AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)>
    public func departuresByBookmark(for bookmarks: [Bookmark], using apiService: RESTAPIService) async
        -> [UUID: [ArrivalDeparture]]
}

extension RESTAPIService {
    public static func standalone(region: Region, apiKey: String, appVersion: String, uuid: String,
                                  dataLoader: URLDataLoader = URLSession.shared) -> RESTAPIService
}
```

**Why a stream and not `async -> [StopID: …]`.** `BookmarkDataLoader` delivers each stop's result to its delegate *as it lands*, and treats a missing-stop error differently from every other error. A dictionary would return only after the slowest stop times out and would flatten the errors. The stream keeps both. `standalone` exists because `APIServiceConfiguration`'s initializer is internal, so code outside OBAKitCore cannot build a `RESTAPIService` today.

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Bookmarks/BookmarkArrivalsLoaderTests.swift`:

```swift
//
//  BookmarkArrivalsLoaderTests.swift
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
final class BookmarkArrivalsLoaderTests: OBATestCase {

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var paths = [String]()

        func record(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            paths.append(path)
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return paths
        }
    }

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    private func mockArrivals(_ dataLoader: MockDataLoader, log: RequestLog, failingStopID: String? = nil) {
        if let failingStopID {
            dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { request in
                request.url?.path.contains(failingStopID) ?? false
            }
        }
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard let path = request.url?.path, path.contains(arrivalsPath) else { return false }
            if let failingStopID, path.contains(failingStopID) { return false }
            log.record(path)
            return true
        }
    }

    @Test func `Two requests at one stop make one network call`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)
        let service = buildRESTService(dataLoader: dataLoader)

        let requests = [
            BookmarkArrivalsRequest(stopID: "1_75414"),
            BookmarkArrivalsRequest(stopID: "1_75414", tripKey: TripBookmarkKey(stopID: "1_75414", routeShortName: "X", routeID: "1_X", tripHeadsign: "Y")),
            BookmarkArrivalsRequest(stopID: "1_10914")
        ]

        var delivered = [StopID]()
        for await (stopID, _) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            delivered.append(stopID)
        }

        #expect(log.all.count == 2)
        #expect(Set(delivered) == ["1_75414", "1_10914"])
        #expect(delivered.count == 2)
    }

    @Test func `No requests finishes immediately with no network calls`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)

        var count = 0
        for await _ in BookmarkArrivalsLoader().arrivals(for: [], using: buildRESTService(dataLoader: dataLoader)) {
            count += 1
        }

        #expect(count == 0)
        #expect(log.all.isEmpty)
    }

    /// One stop failing must not cost the others their data.
    @Test func `A failing stop yields a failure and the rest still succeed`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: "1_BROKEN")
        let service = buildRESTService(dataLoader: dataLoader)

        var results = [StopID: Bool]()
        let requests = [BookmarkArrivalsRequest(stopID: "1_BROKEN"), BookmarkArrivalsRequest(stopID: "1_75414")]
        for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            if case .success = result { results[stopID] = true } else { results[stopID] = false }
        }

        #expect(results == ["1_BROKEN": false, "1_75414": true])
    }

    @Test func `A stop request matches every upcoming departure, soonest first`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json").arrivalsAndDepartures
        let matched = BookmarkArrivalsRequest(stopID: "1_10914").matching(arrivals)

        #expect(matched.allSatisfy { $0.temporalState != .past })
        #expect(matched.map(\.arrivalDepartureDate) == matched.map(\.arrivalDepartureDate).sorted())
    }

    @Test func `A trip request matches only its own trip key`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json").arrivalsAndDepartures
        let first = try #require(arrivals.first)
        let key = TripBookmarkKey(arrivalDeparture: first)

        let matched = BookmarkArrivalsRequest(stopID: first.stopID, tripKey: key).matching(arrivals)

        #expect(matched.isEmpty == false)
        #expect(matched.allSatisfy { TripBookmarkKey(arrivalDeparture: $0) == key })
    }

    @Test func `Departures by bookmark omits a bookmark whose stop failed`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let stops = try Fixtures.loadSomeStops()
        let good = Bookmark(name: "Good", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[0])
        let bad = Bookmark(name: "Bad", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[1])
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: stops[1].id)

        let result = await BookmarkArrivalsLoader().departuresByBookmark(for: [good, bad], using: buildRESTService(dataLoader: dataLoader))

        #expect(result[good.id] != nil)
        #expect(result[bad.id] == nil)
    }

    @Test func `Standalone service targets the region's base URL`() async {
        let service = RESTAPIService.standalone(region: Fixtures.pugetSoundRegion, apiKey: "key", appVersion: "1.0", uuid: "uuid")
        #expect(await service.configuration.baseURL == Fixtures.pugetSoundRegion.OBABaseURL)
        #expect(await service.configuration.regionIdentifier == Fixtures.pugetSoundRegion.regionIdentifier)
    }
}
```

`MockDataLoader` returns the **first** registered mock whose matcher accepts the request, which is why `mockArrivals` registers the failing stop's mock before the catch-all.

- [ ] **Step 2: Run to verify it fails to compile** — `cannot find 'BookmarkArrivalsRequest' in scope`.

- [ ] **Step 3: Implement**

In `TripBookmarkKey.swift:13`:

```swift
public struct TripBookmarkKey: Hashable, Equatable, Sendable {
```

Create `OBAKitCore/Bookmarks/BookmarkArrivalsLoader.swift`:

```swift
//
//  BookmarkArrivalsLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What a caller wants arrivals for: a stop, and optionally one trip at it.
public struct BookmarkArrivalsRequest: Hashable, Sendable {
    public let stopID: StopID
    public let tripKey: TripBookmarkKey?

    public init(stopID: StopID, tripKey: TripBookmarkKey? = nil) {
        self.stopID = stopID
        self.tripKey = tripKey
    }

    public init(bookmark: Bookmark) {
        self.init(stopID: bookmark.stopID, tripKey: TripBookmarkKey(bookmark: bookmark))
    }

    /// The part of a stop's arrivals this request is about: one trip's
    /// departures for a trip request, every upcoming departure (soonest first)
    /// for a stop request.
    public func matching(_ arrivals: [ArrivalDeparture]) -> [ArrivalDeparture] {
        if let tripKey {
            return arrivals.tripKeyGroupedElements[tripKey] ?? []
        }

        return arrivals
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
    }
}

/// Fetches arrivals for a set of bookmarks. Stateless: no timer, no cache, no
/// `CoreApplication`. The iOS app's `BookmarkDataLoader`, the iOS widget, and
/// (later) the watch app and its widget all call this.
public struct BookmarkArrivalsLoader: Sendable {
    private let minutesBefore: UInt
    private let minutesAfter: UInt

    public init(minutesBefore: UInt = 0, minutesAfter: UInt = 60) {
        self.minutesBefore = minutesBefore
        self.minutesAfter = minutesAfter
    }

    /// Streams one result per *distinct stop*, as each fetch lands.
    ///
    /// Requests are deduplicated by stop ID: two trip bookmarks at one stop
    /// cost one network call. A failure is delivered, not thrown, so one bad
    /// stop cannot cost the others their data; callers decide what a given
    /// error means. The stream finishes after the last stop reports.
    public func arrivals(
        for requests: [BookmarkArrivalsRequest],
        using apiService: RESTAPIService
    ) -> AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)> {
        var seen = Set<StopID>()
        let stopIDs = requests.map(\.stopID).filter { seen.insert($0).inserted }
        let (minutesBefore, minutesAfter) = (self.minutesBefore, self.minutesAfter)

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for stopID in stopIDs {
                        group.addTask {
                            do {
                                let arrivals = try await apiService.getArrivalsAndDeparturesForStop(
                                    id: stopID,
                                    minutesBefore: minutesBefore,
                                    minutesAfter: minutesAfter
                                ).entry.arrivalsAndDepartures
                                continuation.yield((stopID, .success(arrivals)))
                            } catch {
                                continuation.yield((stopID, .failure(error)))
                            }
                        }
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects the stream into per-bookmark departures. A bookmark whose stop
    /// failed has **no entry** — distinct from an empty array, which means the
    /// fetch worked and nothing is coming.
    public func departuresByBookmark(
        for bookmarks: [Bookmark],
        using apiService: RESTAPIService
    ) async -> [UUID: [ArrivalDeparture]] {
        let requests = bookmarks.map { ($0.id, BookmarkArrivalsRequest(bookmark: $0)) }

        var arrivalsByStop = [StopID: [ArrivalDeparture]]()
        for await (stopID, result) in arrivals(for: requests.map(\.1), using: apiService) {
            switch result {
            case .success(let arrivals):
                arrivalsByStop[stopID] = arrivals
            case .failure(let error):
                Logger.error("BookmarkArrivalsLoader: arrivals failed for stop \(stopID): \(error.localizedDescription)")
            }
        }

        var result = [UUID: [ArrivalDeparture]]()
        for (bookmarkID, request) in requests {
            if let arrivals = arrivalsByStop[request.stopID] {
                result[bookmarkID] = request.matching(arrivals)
            }
        }
        return result
    }
}

extension RESTAPIService {
    /// Builds a service for `region` without a `CoreApplication`.
    ///
    /// For extensions. `CoreApplication.init` starts a regions fetch, opens the
    /// stop cache, and increments the launch counter that survey gating reads —
    /// none of which a timeline reload should pay for or cause. Do not reach for
    /// `CoreAppConfig(appBundle:)` instead: it builds a `CLLocationManager`.
    public static func standalone(
        region: Region,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared
    ) -> RESTAPIService {
        RESTAPIService(
            APIServiceConfiguration(
                baseURL: region.OBABaseURL,
                apiKey: apiKey,
                uuid: uuid,
                appVersion: appVersion,
                regionIdentifier: region.regionIdentifier
            ),
            dataLoader: dataLoader
        )
    }
}
```

- [ ] **Step 4: Run** `-only-testing:OBAKitTests/BookmarkArrivalsLoaderTests`. Expected: PASS. Then the watchOS device build. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Bookmarks OBAKitTests/Bookmarks/BookmarkArrivalsLoaderTests.swift
git commit -m "Add a stateless, streaming BookmarkArrivalsLoader deduped by stop"
```

### Task 13: `BookmarkDataLoader` adopts the loader

**Files:**
- Modify: `OBAKitCore/Bookmarks/BookmarkDataLoader.swift:170-244`
- Modify: `OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift:51-73` (the private builder **only**)
- Test: `OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift` (add two tests)

**Interfaces:**
- Consumes: `BookmarkArrivalsLoader().arrivals(for:using:)`, `BookmarkArrivalsRequest(stopID:)`.
- Produces: no public API change. Behavior change, deliberate: bookmarks sharing a stop now cost one request, and a failing stop calls `displayError` once rather than once per bookmark at it.

**Exit criterion (see "Deviations", item 1): the three existing test bodies and every assertion in them stay byte-identical.** Only `makeTripBookmarks` changes. Check with `git diff OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift` before committing: the diff may touch the builder and add new tests at the end, nothing else.

The loader's accounting is per *bookmark* (`pendingFetchCount = bookmarks.count`; `isLoading`, `loadDataAndWait()`, and `lastBatchHadError` all hang off it), while results now arrive per *stop*. Each stop therefore settles as many slots as it has bookmarks.

- [ ] **Step 1: Change the builder and add the failing tests**

Replace `makeTripBookmarks` in `BookmarkDataLoaderTests.swift`:

```swift
    /// Builds real *trip* bookmarks — `isTripBookmark` requires a route short
    /// name, route id, and trip headsign, which only a decoded `ArrivalDeparture`
    /// supplies. A bookmark that isn't a trip bookmark is skipped by the loader
    /// without a request, which would silently zero out the counts below.
    ///
    /// Each bookmark gets its **own stop**. The loader fetches a stop once
    /// however many bookmarks share it, so bookmarks at a single stop would
    /// collapse into one request and the counts below would stop measuring
    /// what they are there to measure: which bookmarks were fetched.
    @MainActor
    private func makeTripBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let stops = try Fixtures.loadSomeStops()
        try #require(stops.count >= count)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: pugetSoundRegionIdentifier,
                arrivalDeparture: arrivalDeparture,
                stop: stops[index]
            )
            bookmark.sortOrder = index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }
```

Add at the end of the suite:

```swift
    /// Two trip bookmarks at one stop are one request — and both still settle,
    /// or `loadDataAndWait()` would hang on the second bookmark's slot.
    @Test @MainActor
    func `Bookmarks sharing a stop are fetched once and both settle`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json")
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let shared = (0..<2).map { index in
            Bookmark(name: "Shared \(index)", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture)
        }

        let delegate = RecordingDelegate()
        let loader = BookmarkDataLoader(application: application, delegate: delegate, bookmarkProvider: { shared }, autoRefreshes: false)

        await loader.loadDataAndWait()

        #expect(requestCounter.count == 1)
        #expect(loader.isLoading == false)
        #expect(loader.hasFetchedData(forStopID: arrivalDeparture.stopID))
        #expect(delegate.updateCount == 1)
    }

    /// A stop bookmark reserves a slot and never fetches; it must release it.
    @Test @MainActor
    func `A batch of only stop bookmarks completes without a request`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let stopBookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)

        let loader = BookmarkDataLoader(application: application, delegate: RecordingDelegate(), bookmarkProvider: { [stopBookmark] }, autoRefreshes: false)

        await loader.loadDataAndWait()

        #expect(loader.isLoading == false)
        #expect(loader.hasFetchedData(forStopID: stop.id) == false)
    }
```

- [ ] **Step 2: Run to verify the right tests fail**

Run `-only-testing:OBAKitTests/BookmarkDataLoaderTests`.
Expected: the three existing tests PASS (distinct stops, still one request each); `Bookmarks sharing a stop…` FAILS with `requestCounter.count == 1` → got 2 (and `updateCount` 2); the stop-bookmark test PASSES.

- [ ] **Step 3: Rewrite `startBatch` and `loadData(bookmark:batchID:)`**

Replace both methods (lines 170–244) with:

```swift
    @MainActor private func startBatch(bookmarks: [Bookmark], continuation: CheckedContinuation<Void, Never>?) {
        currentBatchID &+= 1
        let batchID = currentBatchID
        beginBatch(count: bookmarks.count)
        if let continuation {
            if bookmarks.isEmpty {
                continuation.resume()
            } else {
                batchContinuations[batchID, default: []].append(continuation)
            }
        }

        // `beginBatch` reserved one slot per bookmark. Results arrive per *stop*
        // (the loader fetches each stop once), so count how many slots each stop
        // settles, and release at once the slots that will never fetch.
        var slotsByStop = [StopID: Int]()
        for bookmark in bookmarks {
            if application.apiService != nil, bookmark.isTripBookmark {
                slotsByStop[bookmark.stopID, default: 0] += 1
            } else {
                // No fetch will run for this bookmark — release the slot reserved by beginBatch.
                taskFinished(batchID: batchID)
            }
        }

        guard let apiService = application.apiService, !slotsByStop.isEmpty else { return }

        let requests = slotsByStop.keys.map { BookmarkArrivalsRequest(stopID: $0) }
        Task(priority: .userInitiated) {
            for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: apiService) {
                // One task per stop, so a slow `displayError` for one stop
                // does not hold up delivery of the next stop's arrivals.
                Task { @MainActor in
                    await self.settle(result, stopID: stopID, slots: slotsByStop[stopID] ?? 0, batchID: batchID)
                }
            }
        }
    }

    /// Applies one stop's result, then releases the slots of every bookmark at
    /// that stop. The release comes last, as it did when this was a `defer`:
    /// `loadDataAndWait()` must not return before the delegate has been told.
    @MainActor
    private func settle(_ result: Result<[ArrivalDeparture], Error>, stopID: StopID, slots: Int, batchID: UInt64) async {
        defer {
            for _ in 0..<slots { taskFinished(batchID: batchID) }
        }

        // Skip stale completions: a newer batch has already started (or
        // cancelUpdates() retired this one), so writing this fetch's data would
        // overwrite fresher results, and an error would be shown to a consumer
        // that has moved on.
        guard batchID == currentBatchID else { return }

        switch result {
        case .success(let arrivals):
            fetchedStopIDs.insert(stopID)
            for (key, deps) in arrivals.tripKeyGroupedElements {
                tripBookmarkKeys[key] = deps
            }
            delegate?.dataLoaderDidUpdate(self)

        case .failure(let error as APIError) where error.indicatesMissingStop:
            // The stop no longer exists in this region. Don't bulletin —
            // settle the card on "No upcoming departures" and drop any
            // previous countdown for this stop.
            fetchedStopIDs.insert(stopID)
            tripBookmarkKeys = tripBookmarkKeys.filter { $0.key.stopID != stopID }
            delegate?.dataLoaderDidUpdate(self)

        case .failure(let error):
            // Record the failure against the live batch so the batch-complete
            // signal can report whether any fetch errored.
            lastBatchHadError = true
            await application.displayError(error)
        }
    }
```

Two details that are easy to get wrong:

- `taskFinished` already ignores a stale `batchID`, so the `defer` is safe on the stale path.
- The `defer` runs the releases synchronously on the main actor, where the old code hopped through `Task { @MainActor in … }`. That is strictly earlier, never later, and removes a hop; `loadDataAndWait()` callers see the same ordering (delegate told, then resumed).

- [ ] **Step 4: Run the suite and its consumers**

Run `-only-testing:OBAKitTests/BookmarkDataLoaderTests`. Expected: all 5 PASS.
Then `git diff OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift` and confirm the three original test bodies are untouched.
Then `-only-testing:OBAKitTests/BookmarksViewModelTests` — it drives the missing-stop (HTTP 404) path through this loader, which `settle` must still treat as "no departures" and not as an error. Then the full suite, `-only-testing:OBAKitTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Bookmarks/BookmarkDataLoader.swift OBAKitTests/Bookmarks/BookmarkDataLoaderTests.swift
git commit -m "BookmarkDataLoader fetches through BookmarkArrivalsLoader, once per stop"
```

### Task 14: `WidgetTimelinePlanner` — entry dates and the reload date

**Files:**
- Create: `OBAKitCore/Bookmarks/WidgetTimelinePlanner.swift`
- Test: `OBAKitTests/Bookmarks/WidgetTimelinePlannerTests.swift` (create)

**Interfaces:**
- Produces:

```swift
public struct WidgetTimelinePlanner: Sendable {
    public struct Plan: Equatable, Sendable { public let entryDates: [Date]; public let reloadDate: Date }
    public init(minimumEntrySpacing: TimeInterval = 5 * 60, maximumEntries: Int = 12)
    public func plan(departureDates: [Date], now: Date) -> Plan
}
```

It imports only Foundation, so it builds for watchOS and is testable from the iOS-hosted suite. WidgetKit types stay in the widget.

**The budget this protects.** WidgetKit allows 40–70 reloads a *day*. Reloading every 30 minutes across 18 waking hours is 36. **The reload date is never derived from the next departure**: on a 3-minute headway that would ask for 20 reloads an hour. Instead, one reload emits an *entry* at each departure boundary, so the display advances with no reload.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  WidgetTimelinePlannerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite struct WidgetTimelinePlannerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }

    @Test func `No departures is one entry and a sixty minute reload`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [], now: now)

        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(60))
    }

    @Test func `With departures the reload is thirty minutes out`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(10)], now: now)
        #expect(plan.reloadDate == minutes(30))
    }

    /// The defect this type exists to prevent.
    @Test func `An imminent departure does not pull the reload date in`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(1), minutes(4), minutes(7)], now: now)
        #expect(plan.reloadDate == minutes(30))
    }

    @Test func `Unspaced, every departure before the reload is an entry boundary`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0)
        let plan = planner.plan(departureDates: [minutes(12), minutes(3), minutes(10)], now: now)

        #expect(plan.entryDates == [now, minutes(3), minutes(10), minutes(12)])
    }

    @Test func `Boundaries closer than the minimum spacing are coalesced`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(3), minutes(10), minutes(12), minutes(20)], now: now)

        // +3 is within 5 min of `now`; +12 is within 5 min of +10.
        #expect(plan.entryDates == [now, minutes(10), minutes(20)])
    }

    @Test func `Departures at or after the reload date add no entries`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(30), minutes(45)], now: now)
        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(30))
    }

    @Test func `Past departures are ignored, including for the reload interval`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(-5)], now: now)

        #expect(plan.entryDates == [now])
        #expect(plan.reloadDate == minutes(60))
    }

    @Test func `Duplicate departure dates produce one boundary`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0)
        let plan = planner.plan(departureDates: [minutes(8), minutes(8)], now: now)
        #expect(plan.entryDates == [now, minutes(8)])
    }

    @Test func `Entries are capped`() {
        let planner = WidgetTimelinePlanner(minimumEntrySpacing: 0, maximumEntries: 3)
        let plan = planner.plan(departureDates: (1...20).map { minutes(Double($0)) }, now: now)

        #expect(plan.entryDates == [now, minutes(1), minutes(2)])
    }

    @Test func `A full day of reloads stays inside the WidgetKit budget`() {
        let plan = WidgetTimelinePlanner().plan(departureDates: [minutes(10)], now: now)
        let reloadsPerDay = (18 * 60 * 60) / plan.reloadDate.timeIntervalSince(now)
        #expect(reloadsPerDay <= 40)
    }
}
```

- [ ] **Step 2: Run to verify it fails to compile** — `cannot find 'WidgetTimelinePlanner' in scope`.

- [ ] **Step 3: Implement**

Create `OBAKitCore/Bookmarks/WidgetTimelinePlanner.swift`:

```swift
//
//  WidgetTimelinePlanner.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Decides *when* a departures widget shows a new entry and *when* it asks
/// WidgetKit for fresh data. Pure date arithmetic: no WidgetKit, no network.
///
/// The two are different things, and conflating them is expensive. WidgetKit
/// budgets a widget 40–70 reloads a **day**. A reload keyed to the next
/// departure asks for one every few minutes on a frequent route and is
/// throttled within the hour. So: reload on a slow, fixed cadence, and have
/// each reload emit an entry at every departure boundary it already knows
/// about. The display advances as buses leave, at no cost to the budget.
public struct WidgetTimelinePlanner: Sendable {
    public struct Plan: Equatable, Sendable {
        /// When each timeline entry takes effect. Always starts with `now`.
        /// An entry dated `d` should show only departures at or after `d`.
        public let entryDates: [Date]

        /// When to ask WidgetKit for a reload (`.after(reloadDate)`).
        public let reloadDate: Date
    }

    /// 30 min × 18 waking hours = 36 reloads a day, under the 40–70 budget
    /// with room left for reloads the app triggers itself.
    static let reloadIntervalWithDepartures: TimeInterval = 30 * 60

    /// Nothing is coming in the fetched window, so look again less often.
    static let reloadIntervalWithoutDepartures: TimeInterval = 60 * 60

    private let minimumEntrySpacing: TimeInterval
    private let maximumEntries: Int

    /// - Parameter minimumEntrySpacing: Apple recommends entries "at least
    ///   about 5 minutes apart". A multi-bookmark widget has dense boundaries
    ///   and keeps the default; pass 0 for one entry per departure.
    public init(minimumEntrySpacing: TimeInterval = 5 * 60, maximumEntries: Int = 12) {
        self.minimumEntrySpacing = minimumEntrySpacing
        self.maximumEntries = max(1, maximumEntries)
    }

    public func plan(departureDates: [Date], now: Date) -> Plan {
        let upcoming = Set(departureDates.filter { $0 > now }).sorted()

        let interval = upcoming.isEmpty ? Self.reloadIntervalWithoutDepartures : Self.reloadIntervalWithDepartures
        let reloadDate = now.addingTimeInterval(interval)

        var entryDates = [now]
        for boundary in upcoming where boundary < reloadDate {
            guard entryDates.count < maximumEntries else { break }
            if let last = entryDates.last, boundary.timeIntervalSince(last) >= minimumEntrySpacing {
                entryDates.append(boundary)
            }
        }

        return Plan(entryDates: entryDates, reloadDate: reloadDate)
    }
}
```

Note the `minimumEntrySpacing: 0` case: `boundary.timeIntervalSince(last) >= 0` is true for every distinct later boundary, and the `Set` already removed duplicates.

- [ ] **Step 4: Run** `-only-testing:OBAKitTests/WidgetTimelinePlannerTests`. Expected: PASS. Then the watchOS device build. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Bookmarks/WidgetTimelinePlanner.swift OBAKitTests/Bookmarks/WidgetTimelinePlannerTests.swift
git commit -m "Add WidgetTimelinePlanner: departure-boundary entries on a fixed reload cadence"
```

### Task 15: The iOS widget goes stateless

**Files:**
- Rewrite: `OBAWidget/Provider/WidgetDataProvider.swift`
- Modify: `OBAWidget/Entries/BookmarkEntry.swift`
- Modify: `OBAWidget/Provider/BookmarkTimelineProvider.swift`
- Modify: `OBAWidget/Widgets/OBAWidget.swift`, `OBAWidget/Widgets/OBAWidgetEntryView.swift`, `OBAWidget/Views/WidgetRowView.swift:167-171`

**Interfaces:**
- Consumes: `ResolvedRegionStore.region(bundledRegionsFilePath:)`, `UserUUID.value(in:)`, `RESTAPIService.standalone(…)`, `BookmarkArrivalsLoader.departuresByBookmark(for:using:)`, `WidgetTimelinePlanner.plan(departureDates:now:)`.
- Produces: `BookmarkEntry(date:bookmarks:departures:fetchedAt:)`; `WidgetDataProvider.load() async -> WidgetContent`.

OBAWidget has no test target, and none is added: every decision it used to make now lives in OBAKitCore and is covered by Tasks 10–14. What remains here is glue, verified by building and by eye.

What this fixes, for users:
- **Six-hour staleness.** Today the timeline is 12 identical entries with `.atEnd`, so data refreshes about every 6 hours. It becomes a 30-minute `.after` policy.
- **Custom regions.** Today the widget resolves a custom region to nil and shows nothing.
- **"Last updated"** showed each entry's *scheduled* date, so the 1:30 entry claimed a 1:30 update from a 12:00 fetch. It now shows the fetch time.
- **Failed fetches** rendered as "no departures in the next 60 minutes". They now render as "tap for more information", because a bookmark with no data is absent from `departures` rather than mapped to `[]`.
- The widget stops bumping the app's launch counter, which survey gating reads.

- [ ] **Step 1: `BookmarkEntry` carries its data**

Replace the struct in `OBAWidget/Entries/BookmarkEntry.swift`:

```swift
/// A timeline entry for the bookmarks widget. Carries everything its view
/// renders: WidgetKit may draw an entry long after the provider that built it
/// has gone, so a view that reaches back into a shared provider for its
/// arrivals shows whatever that provider happens to hold by then.
struct BookmarkEntry: TimelineEntry {

    let date: Date

    /// bookmarks associated with this `BookmarkEntry`.
    let bookmarks: [Bookmark]

    /// Departures at or after `date`, keyed by `Bookmark.id`. A bookmark that
    /// is **absent** has no data (its fetch failed, or there is no region); one
    /// mapped to `[]` was fetched and has nothing coming.
    let departures: [UUID: [ArrivalDeparture]]

    /// When `departures` was fetched; nil when nothing was.
    let fetchedAt: Date?

    init(date: Date, bookmarks: [Bookmark], departures: [UUID: [ArrivalDeparture]] = [:], fetchedAt: Date? = nil) {
        self.date = date
        self.bookmarks = bookmarks
        self.departures = departures
        self.fetchedAt = fetchedAt
    }

    /// Returns a formatted string representing the last updated time.
    public func lastUpdatedAt(with formatters: Formatters) -> String {
        guard let fetchedAt, !bookmarks.isEmpty else { return "--" }
        return formatters.timeFormatter.string(from: fetchedAt)
    }
}
```

The default arguments keep both `#Preview` blocks (`BookmarkEntry(date: .now, bookmarks: [])`) compiling unchanged.

- [ ] **Step 2: Rewrite `WidgetDataProvider`**

Replace the body of `OBAWidget/Provider/WidgetDataProvider.swift` below the header comment:

```swift
import Foundation
import OBAKitCore

/// What one fetch produced, ready to be sliced into timeline entries.
struct WidgetContent {
    let bookmarks: [Bookmark]
    let departures: [UUID: [ArrivalDeparture]]
    let fetchedAt: Date?

    static let empty = WidgetContent(bookmarks: [], departures: [:], fetchedAt: nil)
}

/// Loads the widget's bookmarks and their arrivals from the app-group suite.
///
/// Deliberately does **not** build a `CoreApplication`. That would start a
/// regions fetch, open and migrate the stop cache, and increment the launch
/// counter that survey gating reads — on every timeline reload, from an
/// extension. Everything the widget needs is in the suite: the bookmarks, the
/// client UUID, and the region the app resolved (`ResolvedRegionStore`), which
/// is also the only way an extension can see a custom region.
@MainActor
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let userDefaults = UserDefaults(suiteName: Bundle.main.appGroup!)!

    /// Formatters for localization and styling.
    let formatters = Formatters(
        locale: Locale.autoupdatingCurrent,
        calendar: Calendar.autoupdatingCurrent,
        themeColors: ThemeColors.shared
    )

    /// Favorited bookmarks in `region`, in the user's order.
    private func bookmarks(in region: Region) -> [Bookmark] {
        UserDefaultsStore(userDefaults: userDefaults).favoritedBookmarks
            .filter { $0.regionIdentifier == region.regionIdentifier }
    }

    func load() async -> WidgetContent {
        let store = ResolvedRegionStore(userDefaults: userDefaults)
        guard let region = store.region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json")) else {
            Logger.error("Widget: no region available.")
            return .empty
        }

        let bookmarks = bookmarks(in: region)
        guard !bookmarks.isEmpty else {
            Logger.info("Widget: no bookmarks to load data for.")
            return .empty
        }

        guard let apiKey = Bundle.main.restServerAPIKey else {
            Logger.error("Widget: no REST API key in the extension's Info.plist.")
            return WidgetContent(bookmarks: bookmarks, departures: [:], fetchedAt: nil)
        }

        let service = RESTAPIService.standalone(
            region: region,
            apiKey: apiKey,
            appVersion: Bundle.main.appVersion,
            uuid: UserUUID.value(in: userDefaults)
        )

        let departures = await BookmarkArrivalsLoader().departuresByBookmark(for: bookmarks, using: service)
        return WidgetContent(bookmarks: bookmarks, departures: departures, fetchedAt: departures.isEmpty ? nil : Date())
    }
}
```

`import CoreLocation` goes away with the `CLLocationManager`. If `UserDefaultsStore.favoritedBookmarks` is not reachable from the extension (it is declared `public` at `UserDataStore.swift:611`), do not widen anything else — report it.

- [ ] **Step 3: Drive the timeline from the planner**

Replace `snapshot` and `timeline` in `BookmarkTimelineProvider.swift`, and delete the long "Generates timeline entries for the next 6 hours" doc comment:

```swift
    // MARK: Snapshot
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> BookmarkEntry {
        let content = await dataProvider.load()
        return BookmarkEntry(date: .now, bookmarks: content.bookmarks, departures: content.departures, fetchedAt: content.fetchedAt)
    }

    // MARK: Actual Timelines
    /// One fetch, several entries, one slow reload.
    ///
    /// `WidgetTimelinePlanner` puts an entry at each departure boundary, so the
    /// widget drops a bus as it leaves without asking for a reload, and sets the
    /// reload 30 minutes out (60 when nothing is coming). Never reload on the
    /// next departure: WidgetKit budgets 40–70 reloads a day.
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<BookmarkEntry> {
        let content = await dataProvider.load()
        let now = Date()

        let plan = WidgetTimelinePlanner().plan(
            departureDates: content.departures.values.flatMap { $0.map(\.arrivalDepartureDate) },
            now: now
        )

        let entries = plan.entryDates.map { date in
            BookmarkEntry(
                date: date,
                bookmarks: content.bookmarks,
                // `mapValues` keeps a fetched-but-now-empty bookmark present
                // (as `[]`), so it reads "no departures", not "no data".
                departures: content.departures.mapValues { $0.filter { $0.arrivalDepartureDate >= date } },
                fetchedAt: content.fetchedAt
            )
        }

        return Timeline(entries: entries, policy: .after(plan.reloadDate))
    }
```

- [ ] **Step 4: Views read from the entry**

`OBAWidget/Widgets/OBAWidgetEntryView.swift` — replace `let dataProvider: WidgetDataProvider` with `let formatters: Formatters`; replace both `dataProvider.formatters` with `formatters`; and replace `loadArrivalDeparture(with:)`:

```swift
    // MARK: Helper functions
    private func loadArrivalDeparture(with bookmark: Bookmark) -> [ArrivalDeparture]? {
        entry.departures[bookmark.id]
    }
```

`OBAWidget/Widgets/OBAWidget.swift` — the closure becomes:

```swift
        let dataProvider = WidgetDataProvider.shared
        return AppIntentConfiguration(
            kind: kind,
            provider: BookmarkTimelineProvider(dataProvider: dataProvider)
        ) { entry in
            OBAWidgetEntryView(entry: entry, formatters: dataProvider.formatters)
                .containerBackground(.fill.quaternary, for: .widget)
        }
```

`WidgetRowView.swift`'s preview still compiles: it reads `WidgetDataProvider.shared.formatters`, which still exists.

- [ ] **Step 5: Build, then check nothing reaches for `CoreApplication`**

```bash
scripts/generate_project OneBusAway && \
SIMULATOR_UDID=$(scripts/resolve_simulator_udid) && \
xcodebuildmcp simulator build-and-run --project-path OBAKit.xcodeproj --scheme App --simulator-id "$SIMULATOR_UDID"
grep -rn "CoreApplication\|CoreAppConfig\|CLLocationManager\|refreshServices" OBAWidget --include="*.swift"
```

Expected: the build succeeds, and the `grep` prints nothing.

- [ ] **Step 6: Verify by eye**

Widget placement cannot be scripted. On the simulator:

1. In the app, favorite two bookmarks at different stops. Add the medium widget to the Home Screen.
2. Expected: both rows show departures; "Last updated at" shows the current time.
3. Confirm the persisted region exists: `xcrun simctl spawn "$SIMULATOR_UDID" defaults read group.org.onebusaway.iphone OBAResolvedCurrentRegion | head -3` prints data, not "does not exist".
4. Custom region: open `onebusaway://add-region?name=Probe&oba-url=https%3A%2F%2Fapi.pugetsound.onebusaway.org` with `xcrun simctl openurl "$SIMULATOR_UDID" "<that URL>"`, select it, favorite a bookmark in it, and confirm the widget shows that bookmark's departures. Before this PR it showed nothing.

Record the result of each in the PR description. If step 4 cannot be completed in the simulator, say so rather than claiming it.

- [ ] **Step 7: Commit**

```bash
git add OBAWidget
git commit -m "iOS widget: stateless arrivals, entries that carry data, 30-minute reloads"
```

### Task 16: PR 3 gate

- [ ] **Step 1:** Full unit suite, `-only-testing:OBAKitTests`. Expected: PASS.
- [ ] **Step 2:** watchOS device-architecture build. Expected: `BUILD SUCCEEDED`.
- [ ] **Step 3:** `swiftlint lint --quiet; echo "exit: $?"`. Expected: no errors.
- [ ] **Step 4:** `scripts/extract_strings && git diff --stat OBAKitCore/Strings OBAKit/Strings`. Expected: empty (this PR adds no user-facing strings).
- [ ] **Step 5:** Open the PR. Title: `watchOS step 3: stateless arrivals loader; fixes widget staleness and custom regions`. The body lists the five user-visible widget fixes from Task 15 and the one behavior change in `BookmarkDataLoader` (one request and one error per stop).

---

## What this plan leaves for the next ones

- **Step 0** (its own short plan): `.supplementalActivityFamilies([.small, .medium])` and an `activityFamily == .small` branch in `TripLiveActivityCardView`.
- **Step 4:** `WatchSyncPayload`, `WatchBookmark`, `WatchSessionBridge`, the sender, `.bookmarkGroupsDidChange`.
- **Step 5:** OBAKitWatch, WatchApp, `watch.yml` / `--no-watch`, `requestLocation()` and `desiredAccuracy` on `LocationManager`, the configurable request timeout, the launch smoke test, and the manual pass on a physical 32-bit watch. The CI step from Task 9 switches its scheme to `WatchApp`.
- **Step 6:** OBAWatchWidget, `DepartureSnapshot` and `OBAWidgetShared/`, `Text(timerInterval:countsDown:)`, the overnight reload rule, `relevance()`.

Feed the list of second-layer fixes recorded in Task 8 into those plans before writing them.
