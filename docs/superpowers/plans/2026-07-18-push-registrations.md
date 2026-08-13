# OBACloud Push Registrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Issue:** https://github.com/OneBusAway/onebusaway-ios/issues/1204

**Goal:** Proactively register the device's APNs push token (with locale and `test_device` flag) against the OBACloud `push_registrations` API — on launch/foreground, on token rotation, and on region change — so agencies can send service-alert push notifications to opted-in riders.

**Architecture:** Two new form-encoded endpoints on the existing `ObacoAPIService` actor (mirroring `postAlarm`/`deleteAlarm`); a new `@MainActor` `PushRegistrationManager` in OBAKit that owns dedupe/staleness logic and persists the last registration to UserDefaults; a token-update callback threaded through the existing `PushServiceProvider` → `PushService` → `PushServiceDelegate` chain; trigger wiring in `Application` (`applicationDidBecomeActive`, `regionsService(_:updatedRegion:)`, and the new delegate method).

**Tech Stack:** Swift 6, XCTest (+ existing `MockDataLoader`/`OBATestCase` harness), XcodeGen, no new dependencies.

## Global Constraints

- **`test_device` must be sent on every POST** — the server upsert resets an omitted `test_device` to `false`. Send it explicitly, always.
- `test_device` value: `true` for DEBUG builds; for release builds, `true` only when the user has enabled the hidden "Debug Mode" setting (`userDataStore.debugMode`) — the issue's "internal developer setting" option. (No receipt/TestFlight detection: `Bundle.appStoreReceiptURL` is deprecated on iOS 18.)
- `operating_system` is the literal string `"ios"` (matches the existing alarm POST).
- `locale` is `Locale.current.identifier(.bcp47)` — the server wants BCP-47 (`es-MX`, `zh-Hant-TW`); `Locale.current.identifier` alone yields POSIX-style `es_MX`. Do not otherwise normalize; the server maps it.
- Bodies are form-urlencoded via `NetworkHelpers.dictionary(toHTTPBodyData:)` and sent through `APIService.data(for:)` — do **not** use the JSON `sendData`/`postData` path. Success is `204 No Content`; the existing `data(for:)` already treats empty non-GET 2xx as success.
- OBAKitCore must remain application-extension safe: `ObacoAPIService` changes touch no UIKit. All UIKit usage (`UIApplication.shared.registerForRemoteNotifications()`) stays in OBAKit.
- After **creating any new file**, run `scripts/generate_project OneBusAway` before building (XcodeGen project; new files are invisible until regeneration).
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro`. When piping `xcodebuild`, use `set -o pipefail` so failures aren't masked.
- Work happens on the current `service-alerts` branch (currently identical to `main`).
- Rate limit is 30 req/min/IP — the manager's dedupe (only re-POST on change or after 24h) keeps us far below it.

**Out of scope (explicitly):** in-app opt-out UI (the DELETE endpoint is implemented and tested, but nothing calls it yet); DELETE from the *old* region on region change (server-side 180-day prune + APNs bounce feedback handle stale rows); deep-linking from the notification (needs a server payload addition first). The notification itself is plain `title`+`body` — the existing `UNUserNotificationCenterDelegate` in `OBACloudPushService` already displays it; no new receive-side code is added. One pre-existing nuance to mention in the PR body: tapping such a notification routes its single-key `userInfo` through `PushService.notificationReceivedHandler` into `displayMessage(_:)` (`PushService.swift:95-106`), so the app re-presents the alert body in an in-app dialog after opening. That is existing behavior, not a regression.

**Authorization gate:** register when the notification authorization status is `.authorized`, `.provisional`, or `.ephemeral` — provisionally-authorized users receive quiet notifications and are exactly the riders the issue wants counted. Never register for `.denied` or `.notDetermined`.

---

### Task 1: `push_registrations` endpoints on `ObacoAPIService`

**Files:**
- Modify: `OBAKitCore/Network/ObacoAPIService.swift` (regionID visibility at ~line 26; new methods after `deleteAlarm`, ~line 160)
- Create: `OBAKitTests/Modeling/Obaco Model Service Tests/PushRegistrationModelOperationTests.swift`

**Interfaces:**
- Consumes: existing `buildURL(path:queryItems:)`, `NetworkHelpers.dictionary(toHTTPBodyData:)`, `data(for:)`.
- Produces (Tasks 2–4 rely on these exact signatures):
  - `public nonisolated let regionID: RegionIdentifier` (was `private let`)
  - `public nonisolated func postPushRegistration(token: String, locale: String, testDevice: Bool) async throws`
  - `@discardableResult public nonisolated func deletePushRegistration(token: String) async throws -> (Data, URLResponse)`

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/Modeling/Obaco Model Service Tests/PushRegistrationModelOperationTests.swift`:

```swift
//
//  PushRegistrationModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

/// Tests for the OBACloud `push_registrations` API (issue #1204): registering the
/// device's APNs token so agencies can push service alerts to opted-in riders.
class PushRegistrationModelOperationTests: OBATestCase {

    /// Captures the body of the request the service actually put on the wire. Single
    /// request per test, written before the mock returns and read after the `await`
    /// resumes, so there's no concurrent access in practice.
    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var body: String?
        nonisolated(unsafe) var url: URL?
    }

    private func mockRegistrationPOST(statusCode: Int = 204) -> RequestCapture {
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/push_registrations") ?? false else {
                return false
            }
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            capture.url = request.url
            return true
        }
        return capture
    }

    func testSuccessfulRegistration_sendsAllContractParams() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "es-MX", testDevice: false)

        let body = try XCTUnwrap(capture.body, "Expected postPushRegistration to send a form-encoded body")
        XCTAssertTrue(body.contains("token=01abff007f"), "Body: \(body)")
        XCTAssertTrue(body.contains("operating_system=ios"), "Body: \(body)")
        XCTAssertTrue(body.contains("locale=es-MX"), "Body: \(body)")
        // The server upserts on every call and an omitted test_device resets the stored
        // value to false — the param's *presence* on every request is contract, not just
        // its value.
        XCTAssertTrue(body.contains("test_device=false"), "Body: \(body)")
    }

    func testRegistration_flagsTestDevices() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: true)

        let body = try XCTUnwrap(capture.body)
        XCTAssertTrue(body.contains("test_device=true"), "Body: \(body)")
    }

    func testRegistration_targetsRegionScopedURL() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: false)

        let url = try XCTUnwrap(capture.url)
        XCTAssertTrue(
            url.absoluteString.starts(with: "https://alerts.example.com/api/v2/regions/1/push_registrations"),
            "URL: \(url.absoluteString)")
    }

    /// The server answers validation failures with a 422 — that must surface as an error.
    func testRegistrationValidationFailureThrows() async throws {
        _ = mockRegistrationPOST(statusCode: 422)

        do {
            try await obacoService.postPushRegistration(token: "", locale: "en-US", testDevice: false)
            XCTFail("Expected postPushRegistration to throw APIError.requestFailure")
        } catch let error as APIError {
            guard case .requestFailure = error else {
                XCTFail("Expected APIError.requestFailure, got \(error)")
                return
            }
        }
    }

    func testSuccessfulUnregistration() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: 204) { request in
            request.httpMethod == "DELETE" &&
            (request.url?.path.hasSuffix("/push_registrations") ?? false) &&
            (request.url?.query?.contains("token=01abff007f") ?? false)
        }

        let (_, response) = try await obacoService.deletePushRegistration(token: "01abff007f")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 204)
    }

    /// A 404 means the token was never registered — safe for callers to ignore, but the
    /// service layer still surfaces it faithfully.
    func testUnregistrationWith404Throws() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: 404) { request in
            request.httpMethod == "DELETE" &&
            (request.url?.path.hasSuffix("/push_registrations") ?? false)
        }

        do {
            _ = try await obacoService.deletePushRegistration(token: "01abff007f")
            XCTFail("Expected deletePushRegistration to throw APIError.requestNotFound")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                XCTFail("Expected APIError.requestNotFound, got \(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate the project and run the tests to verify they fail**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with `value of type 'ObacoAPIService' has no member 'postPushRegistration'` (compile error is the failing state for a new API).

- [ ] **Step 3: Implement the endpoints**

In `OBAKitCore/Network/ObacoAPIService.swift`, change the `regionID` declaration (~line 26) from:

```swift
    private let regionID: RegionIdentifier
```

to (Task 2's manager reads it cross-module to key its dedupe state on the region actually targeted):

```swift
    public nonisolated let regionID: RegionIdentifier
```

Then add after `deleteAlarm(url:)` (~line 160):

```swift
    // MARK: - Push Registrations

    /// Registers — or refreshes — this device's APNs push token with the OBACloud server so the
    /// region's transit agencies can send service-alert push notifications to it.
    ///
    /// The server upserts on `(region, token)`, so create and update are the same call. A
    /// successful response is a bare `204 No Content`.
    ///
    /// - Parameters:
    ///   - token: The hex-encoded APNs device token.
    ///   - locale: The device's BCP-47 locale identifier (e.g. `"es-MX"`), used by the server to
    ///     pick the alert translation. Sent as-reported; the server does its own mapping.
    ///   - testDevice: Whether this device should receive "Test users only" sends. The server
    ///     resets an omitted value to `false` on every upsert, so it is always sent explicitly.
    public nonisolated func postPushRegistration(token: String, locale: String, testDevice: Bool) async throws {
        let url = await buildURL(path: String(format: "/api/v2/regions/%d/push_registrations", regionID))
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        let params: [String: Any] = [
            "token": token,
            "operating_system": "ios",
            "locale": locale,
            "test_device": testDevice ? "true" : "false"
        ]

        urlRequest.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: params)

        _ = try await data(for: urlRequest as URLRequest)
    }

    /// Removes this device's push registration from the OBACloud server.
    ///
    /// The token travels as a query item; the server is a Rails app whose `params` merge query
    /// and body, and its own request spec exercises DELETE this way.
    ///
    /// Answers `204` on success and `404` if the token was never registered — the latter throws
    /// `APIError.requestNotFound`, which callers may safely ignore.
    @discardableResult
    public nonisolated func deletePushRegistration(token: String) async throws -> (Data, URLResponse) {
        let url = await buildURL(
            path: String(format: "/api/v2/regions/%d/push_registrations", regionID),
            queryItems: [URLQueryItem(name: "token", value: token)])
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await data(for: request as URLRequest)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/PushRegistrationModelOperationTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: `Test Suite 'PushRegistrationModelOperationTests' passed` — 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add OBAKitCore/Network/ObacoAPIService.swift "OBAKitTests/Modeling/Obaco Model Service Tests/PushRegistrationModelOperationTests.swift"
git commit -m "Add OBACloud push_registrations API endpoints to ObacoAPIService (#1204)"
```

---

### Task 2: `PushRegistrationManager`

**Files:**
- Create: `OBAKit/PushNotifications/PushRegistrationManager.swift`
- Create: `OBAKitTests/PushNotifications/PushRegistrationManagerTests.swift`

**Interfaces:**
- Consumes: `ObacoAPIService.postPushRegistration(token:locale:testDevice:)` and `ObacoAPIService.regionID` from Task 1; `Logger` from OBAKitCore.
- Produces (Tasks 3–4 rely on these exact signatures):
  - `@MainActor public final class PushRegistrationManager: NSObject`
  - `public init(obacoServiceProvider:userDefaults:testDeviceProvider:currentRegionIdentifierProvider:authorizationStatusProvider:localeProvider:dateProvider:requestRemoteNotificationsRegistration:)` — last four have defaults
  - `public func updateDeviceToken(_ token: String)` — stores only; side-effect free
  - `public func registerIfNeeded() async` — POSTs iff something changed or the last POST is >24h old
  - `public func refreshRegistration() async` — auth check → `registerForRemoteNotifications()` → `registerIfNeeded()`

- [ ] **Step 1: Write the failing tests**

Create `OBAKitTests/PushNotifications/PushRegistrationManagerTests.swift`:

```swift
//
//  PushRegistrationManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import UserNotifications
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `PushRegistrationManager` (issue #1204): keeping the device's APNs token
/// registered with the current region's OBACloud server — deduplicated, daily-refreshed,
/// and gated on notification authorization.
@MainActor
class PushRegistrationManagerTests: OBATestCase {

    /// Mutable state shared with the manager's injected closures. `@unchecked Sendable`
    /// because tests mutate it only between awaited calls.
    private final class Controls: @unchecked Sendable {
        var authorizationStatus: UNAuthorizationStatus = .authorized
        var locale = "en-US"
        var testDevice = false
        var currentRegionID: Int? = 1
        var now = Date(timeIntervalSince1970: 1_752_800_000)
        var remoteRegistrationRequests = 0
        /// When true, the next auth-status check parks on `authGate` until the test resumes it —
        /// lets the coalescing test hold a registration mid-flight deterministically.
        var holdNextAuthCheck = false
        var authGate: CheckedContinuation<Void, Never>?
    }

    private var controls: Controls!
    private var dataLoader: MockDataLoader!
    private var currentService: ObacoAPIService?
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        controls = Controls()
        dataLoader = MockDataLoader(testName: name)
        currentService = buildObacoService(dataLoader: dataLoader)
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    /// Mocks the `POST /push_registrations` response. Installed per-test rather than in
    /// `setUp` because `MockDataLoader` matching is first-added-wins and the
    /// failure-handling test needs a non-204 answer.
    private func mockRegistrationResponse(statusCode: Int = 204) {
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            request.httpMethod == "POST" && (request.url?.path.hasSuffix("/push_registrations") ?? false)
        }
    }

    private func makeManager() -> PushRegistrationManager {
        let controls = self.controls!
        return PushRegistrationManager(
            obacoServiceProvider: { [weak self] in self?.currentService },
            userDefaults: defaults,
            testDeviceProvider: { controls.testDevice },
            currentRegionIdentifierProvider: { controls.currentRegionID },
            authorizationStatusProvider: {
                if controls.holdNextAuthCheck {
                    controls.holdNextAuthCheck = false
                    await withCheckedContinuation { controls.authGate = $0 }
                }
                return controls.authorizationStatus
            },
            localeProvider: { controls.locale },
            dateProvider: { controls.now },
            requestRemoteNotificationsRegistration: { controls.remoteRegistrationRequests += 1 }
        )
    }

    private var registrationRequestCount: Int {
        dataLoader.recordedRequestURLs.filter { $0.path.hasSuffix("/push_registrations") }.count
    }

    // MARK: - Registration

    func test_registerIfNeeded_postsTokenOnce() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 1)

        // Nothing changed: an immediate second call must not hit the network again.
        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 1)
    }

    func test_registerIfNeeded_withoutToken_doesNothing() async {
        let manager = makeManager()
        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 0)
    }

    func test_registerIfNeeded_withoutAuthorization_doesNothing() async {
        controls.authorizationStatus = .denied
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 0)
    }

    /// Provisionally-authorized users receive quiet notifications — they count as opted in.
    func test_registerIfNeeded_registersWithProvisionalAuthorization() async {
        controls.authorizationStatus = .provisional
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 1)
    }

    /// `CoreApplication.refreshObacoService()` leaves the previous region's service in place
    /// when the user switches to a region without a sidecar — never register against a region
    /// the user has left.
    func test_registerIfNeeded_skipsWhenObacoServiceRegionIsStale() async {
        controls.currentRegionID = 99
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 0)
    }

    func test_registerIfNeeded_withoutObacoService_doesNothing() async {
        currentService = nil
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 0)
    }

    // MARK: - Re-registration triggers

    func test_registerIfNeeded_repostsWhenTokenRotates() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        manager.updateDeviceToken("cafed00d")
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2)
    }

    func test_registerIfNeeded_repostsWhenLocaleChanges() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.locale = "es-MX"
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2)
    }

    func test_registerIfNeeded_repostsWhenTestDeviceFlagChanges() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.testDevice = true
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2)
    }

    func test_registerIfNeeded_repostsWhenRegionChanges() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 1)

        // Same host, different region — mirrors CoreApplication rebuilding obacoService
        // after a region switch.
        let config = APIServiceConfiguration(baseURL: obacoURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: 2)
        currentService = ObacoAPIService(regionID: 2, delegate: nil, configuration: config, dataLoader: dataLoader)
        controls.currentRegionID = 2

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 2)
        XCTAssertTrue(dataLoader.recordedRequestURLs.contains { $0.path.hasSuffix("/regions/2/push_registrations") })
    }

    /// The server prunes tokens not seen for 180 days; an unchanged registration is
    /// therefore re-POSTed once its age exceeds the refresh interval.
    func test_registerIfNeeded_repostsWhenStale() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.now = controls.now.addingTimeInterval(PushRegistrationManager.refreshInterval + 60)
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2)
    }

    /// Dedupe state persists across manager instances (i.e., app launches).
    func test_registerIfNeeded_dedupeSurvivesRelaunch() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        let relaunched = makeManager()
        relaunched.updateDeviceToken("01abff007f")
        await relaunched.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 1)
    }

    // MARK: - Failure handling

    /// A failed POST must not be recorded as a successful registration — the next call retries.
    func test_registerIfNeeded_doesNotPersistOnServerError() async {
        mockRegistrationResponse(statusCode: 422)

        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2, "Expected a retry because the first POST failed")
    }

    // MARK: - Coalescing

    /// On the first foreground after a permission grant, the becomeActive trigger and the
    /// APNs token callback can both call `registerIfNeeded()` before either finishes — the
    /// second caller must coalesce into the first instead of double-POSTing.
    func test_registerIfNeeded_coalescesConcurrentCalls() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        // Hold the first registration at its auth check, mid-flight.
        controls.holdNextAuthCheck = true
        let first = Task { await manager.registerIfNeeded() }
        while controls.authGate == nil { await Task.yield() }

        // A second trigger arrives while the first is parked: it must return immediately
        // after handing its work to the in-flight pass.
        await manager.registerIfNeeded()

        controls.authGate?.resume()
        controls.authGate = nil
        _ = await first.value

        XCTAssertEqual(registrationRequestCount, 1)
    }

    // MARK: - refreshRegistration

    func test_refreshRegistration_requestsAPNsRegistrationWhenAuthorized() async {
        let manager = makeManager()
        await manager.refreshRegistration()
        XCTAssertEqual(controls.remoteRegistrationRequests, 1)
    }

    func test_refreshRegistration_skipsAPNsRegistrationWhenDenied() async {
        controls.authorizationStatus = .denied
        let manager = makeManager()
        await manager.refreshRegistration()
        XCTAssertEqual(controls.remoteRegistrationRequests, 0)
        XCTAssertEqual(registrationRequestCount, 0)
    }
}
```

**Note for the implementer:** `OBATestCase` exposes `obacoURL`, `apiKey`, `uuid`, `appVersion`, and `buildObacoService(dataLoader:)` (see `OBAKitTests/Helpers/OBATestCase.swift:74-77`); `MockDataLoader.mock(data:statusCode:matcher:)` and `recordedRequestURLs` are at `OBAKitTests/Helpers/Mocks/MockDataLoader.swift:144` and `:61`.

- [ ] **Step 2: Regenerate the project and verify the tests fail**

```bash
scripts/generate_project OneBusAway
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** with `cannot find 'PushRegistrationManager' in scope`.

- [ ] **Step 3: Implement `PushRegistrationManager`**

Create `OBAKit/PushNotifications/PushRegistrationManager.swift`:

```swift
//
//  PushRegistrationManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import UserNotifications
import OBAKitCore

/// Keeps this device's APNs push token registered with the current region's OBACloud server
/// so transit agencies can send service-alert push notifications to it.
///
/// Historically the server only learned tokens as a side effect of alarm creation, which
/// misses riders who never set an alarm, carries no locale for translated alert copy, and
/// lets tokens age past the server's 180-day prune. This manager registers proactively:
/// `Application` calls ``refreshRegistration()`` on every foreground, feeds rotated tokens in
/// via ``updateDeviceToken(_:)`` + ``registerIfNeeded()``, and calls ``registerIfNeeded()``
/// again after a region change.
///
/// The last successful registration (token, region, locale, test-device flag, timestamp) is
/// persisted to user defaults; an unchanged registration is re-POSTed only after
/// ``refreshInterval`` elapses, which keeps traffic well under the server's rate limit while
/// still refreshing `last_seen_at` ahead of the prune.
@MainActor
public final class PushRegistrationManager: NSObject {

    public typealias AuthorizationStatusProvider = @Sendable () async -> UNAuthorizationStatus

    /// The inputs that determine whether a new POST is needed, plus when the last one happened.
    private struct Registration: Codable {
        let token: String
        let regionID: RegionIdentifier
        let locale: String
        let testDevice: Bool
        let registeredAt: Date

        /// Equivalence over everything except `registeredAt` — age is checked separately.
        func isEquivalent(to other: Registration) -> Bool {
            token == other.token &&
            regionID == other.regionID &&
            locale == other.locale &&
            testDevice == other.testDevice
        }
    }

    /// Re-POST an otherwise-unchanged registration this often so the server's 180-day
    /// `last_seen_at` prune never drops this device.
    nonisolated public static let refreshInterval: TimeInterval = 60 * 60 * 24

    nonisolated static let lastRegistrationUserDefaultsKey = "PushRegistrationManager.lastRegistration"

    private let obacoServiceProvider: () -> ObacoAPIService?
    private let userDefaults: UserDefaults
    private let testDeviceProvider: () -> Bool
    private let currentRegionIdentifierProvider: () -> RegionIdentifier?
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let localeProvider: () -> String
    private let dateProvider: () -> Date
    private let requestRemoteNotificationsRegistration: () -> Void

    private(set) var deviceToken: String?

    /// Coalescing state: `registrationInProgress` is held for the duration of a registration
    /// pass; a caller arriving mid-flight sets `needsAnotherPass` and returns, and the holder
    /// loops once more (the dedupe check makes a redundant pass a no-op).
    private var registrationInProgress = false
    private var needsAnotherPass = false

    /// - Parameters:
    ///   - obacoServiceProvider: Resolves the current region's Obaco service on each call —
    ///     the service is recreated whenever the region changes, so it must not be captured.
    ///   - userDefaults: Backing store for the last-registration dedupe state.
    ///   - testDeviceProvider: Whether this install should receive "Test users only" sends.
    ///   - currentRegionIdentifierProvider: The user's current region. Guards against the
    ///     stale-`obacoService` case: switching to a region without a sidecar leaves the old
    ///     region's service in place, and we must never register against a region the user left.
    ///   - authorizationStatusProvider: Injectable for tests; defaults to the real
    ///     notification-center authorization status.
    ///   - localeProvider: Injectable for tests; defaults to the device's BCP-47 identifier.
    ///   - dateProvider: Injectable for tests; defaults to `Date()`.
    ///   - requestRemoteNotificationsRegistration: Injectable for tests; defaults to
    ///     `UIApplication.shared.registerForRemoteNotifications()`.
    public init(
        obacoServiceProvider: @escaping () -> ObacoAPIService?,
        userDefaults: UserDefaults,
        testDeviceProvider: @escaping () -> Bool,
        currentRegionIdentifierProvider: @escaping () -> RegionIdentifier?,
        authorizationStatusProvider: @escaping AuthorizationStatusProvider = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        localeProvider: @escaping () -> String = { Locale.current.identifier(.bcp47) },
        dateProvider: @escaping () -> Date = { Date() },
        requestRemoteNotificationsRegistration: @escaping () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        }
    ) {
        self.obacoServiceProvider = obacoServiceProvider
        self.userDefaults = userDefaults
        self.testDeviceProvider = testDeviceProvider
        self.currentRegionIdentifierProvider = currentRegionIdentifierProvider
        self.authorizationStatusProvider = authorizationStatusProvider
        self.localeProvider = localeProvider
        self.dateProvider = dateProvider
        self.requestRemoteNotificationsRegistration = requestRemoteNotificationsRegistration
    }

    /// Stores the latest hex-encoded APNs token. Side-effect free — follow with
    /// ``registerIfNeeded()``. Called from the push provider's token callback, which fires on
    /// every `registerForRemoteNotifications()` including token rotations.
    public func updateDeviceToken(_ token: String) {
        deviceToken = token
    }

    /// Asks the OS for a (possibly rotated) device token and registers whatever token is
    /// already known. Call on every app foreground: the token callback re-enters via
    /// ``updateDeviceToken(_:)`` + ``registerIfNeeded()``, so a rotated token is registered
    /// as soon as APNs delivers it. No-ops unless notification permission is granted.
    public func refreshRegistration() async {
        guard await isAuthorized() else { return }
        requestRemoteNotificationsRegistration()
        await registerIfNeeded()
    }

    /// POSTs the current token to the current region's Obaco server — but only if the token,
    /// region, locale, or test-device flag changed since the last successful POST, or that
    /// POST is older than ``refreshInterval``. No-ops without a token, an Obaco service, or
    /// notification permission. Concurrent calls coalesce: on the first foreground after a
    /// permission grant, the becomeActive trigger and the APNs token callback can overlap,
    /// and only one POST should result.
    public func registerIfNeeded() async {
        guard !registrationInProgress else {
            // An in-flight pass will loop and re-read all inputs (including a token that
            // rotated underneath it) — nothing is lost by returning here.
            needsAnotherPass = true
            return
        }

        registrationInProgress = true
        defer { registrationInProgress = false }

        repeat {
            needsAnotherPass = false
            await performRegistrationIfNeeded()
        } while needsAnotherPass
    }

    private func performRegistrationIfNeeded() async {
        guard
            let deviceToken,
            let obacoService = obacoServiceProvider(),
            // Switching to a region without a sidecar leaves the previous region's service in
            // place (CoreApplication.refreshObacoService early-returns) — never register
            // against a region the user left.
            obacoService.regionID == currentRegionIdentifierProvider(),
            await isAuthorized()
        else { return }

        let candidate = Registration(
            token: deviceToken,
            regionID: obacoService.regionID,
            locale: localeProvider(),
            testDevice: testDeviceProvider(),
            registeredAt: dateProvider())

        if let last = lastRegistration,
           last.isEquivalent(to: candidate),
           candidate.registeredAt.timeIntervalSince(last.registeredAt) < Self.refreshInterval {
            return
        }

        do {
            try await obacoService.postPushRegistration(
                token: candidate.token,
                locale: candidate.locale,
                testDevice: candidate.testDevice)
            lastRegistration = candidate
        } catch {
            // Leave `lastRegistration` untouched so the next trigger retries.
            Logger.error("Push registration failed: \(error)")
        }
    }

    /// Provisional and ephemeral authorization still deliver notifications — those riders
    /// count as opted in. Only `.denied`/`.notDetermined` block registration.
    private func isAuthorized() async -> Bool {
        switch await authorizationStatusProvider() {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    private var lastRegistration: Registration? {
        get {
            guard let data = userDefaults.data(forKey: Self.lastRegistrationUserDefaultsKey) else { return nil }
            return try? JSONDecoder().decode(Registration.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                userDefaults.removeObject(forKey: Self.lastRegistrationUserDefaultsKey)
                return
            }
            userDefaults.set(data, forKey: Self.lastRegistrationUserDefaultsKey)
        }
    }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

```bash
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/PushRegistrationManagerTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: `Test Suite 'PushRegistrationManagerTests' passed` — 16 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/PushNotifications/PushRegistrationManager.swift OBAKitTests/PushNotifications/PushRegistrationManagerTests.swift
git commit -m "Add PushRegistrationManager with dedupe and daily refresh (#1204)"
```

---

### Task 3: Thread token updates through the push service chain into `Application`

**Files:**
- Modify: `OBAKit/PushNotifications/PushService.swift` (protocol at lines 29-40, delegate at lines 44-48, init at lines 58-66)
- Modify: `OBAKit/PushNotifications/OBACloudPushService.swift` (property near line 31, `didRegisterForRemoteNotifications` at lines 105-116)
- Modify: `OBAKit/Orchestration/Application.swift` (push notifications section, lines 282-318)
- Modify: `OBAKitTests/PushNotifications/PushServiceTests.swift` (mock provider at line 17, delegate recorder at line 38)
- Modify: `OBAKitTests/PushNotifications/OBACloudPushServiceTests.swift`
- Modify: `OBAKitTests/Application/ApplicationTests.swift` (`MockPushServiceProvider` at line 723)

**Interfaces:**
- Consumes: `PushRegistrationManager` (Task 2), `PushManagerUserIDCallback` (existing typealias `(String) -> Void`).
- Produces:
  - `PushServiceProvider` gains `var deviceTokenUpdatedHandler: PushManagerUserIDCallback? { get set }`
  - `PushServiceDelegate` gains `func pushService(_ pushService: PushService, receivedDeviceToken token: String)`
  - `Application.pushRegistrationManager: PushRegistrationManager` (public, lazy)

- [ ] **Step 1: Write the failing tests**

In `OBAKitTests/PushNotifications/OBACloudPushServiceTests.swift`, add inside the class:

```swift
    // MARK: - Token Update Handler

    func test_didRegister_invokesDeviceTokenUpdatedHandlerOnEveryRegistration() {
        var receivedTokens: [String] = []
        service.deviceTokenUpdatedHandler = { receivedTokens.append($0) }

        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))
        // Token rotation (restore/reinstall) re-fires the handler with the new token.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

        XCTAssertEqual(receivedTokens, ["beef", "cafe"])
    }
```

In `OBAKitTests/PushNotifications/PushServiceTests.swift`, add a `receivedDeviceTokens` recorder and a test. In `PushServiceDelegateRecorder` (line 38), add:

```swift
    var receivedDeviceTokens: [String] = []

    func pushService(_ pushService: PushService, receivedDeviceToken token: String) {
        receivedDeviceTokens.append(token)
    }
```

In `RecordingPushServiceProvider` (line 17), add:

```swift
    var deviceTokenUpdatedHandler: PushManagerUserIDCallback?
```

Then add this test to the test class body:

```swift
    func test_deviceTokenUpdates_areForwardedToDelegate() {
        XCTAssertNotNil(provider.deviceTokenUpdatedHandler, "PushService must install the token handler during init")

        provider.deviceTokenUpdatedHandler?("01abff007f")

        XCTAssertEqual(delegate.receivedDeviceTokens, ["01abff007f"])
    }
```

In `OBAKitTests/Application/ApplicationTests.swift`, `MockPushServiceProvider` (line 723), add the same property:

```swift
    var deviceTokenUpdatedHandler: PushManagerUserIDCallback?
```

- [ ] **Step 2: Build to verify the failure**

```bash
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: **build FAILS** — the two new tests reference `deviceTokenUpdatedHandler`, which exists on neither `OBACloudPushService` nor the provider protocol yet. (The delegate recorder's extra method compiles fine on its own — an unmatched method is not an error — so the failure comes from the handler references.)

- [ ] **Step 3: Implement the plumbing**

In `OBAKit/PushNotifications/PushService.swift`:

Add to the `PushServiceProvider` protocol (after the `errorHandler` requirement, line 37):

```swift
    /// Called with the hex-encoded APNs token every time the device (re-)registers with APNs,
    /// including token rotations. Set by ``PushService`` during initialization.
    var deviceTokenUpdatedHandler: PushManagerUserIDCallback? { get set }
```

Add to `PushServiceDelegate` (after `receivedDonationPrompt`, line 47):

```swift
    /// Called whenever APNs issues the device a (possibly rotated) push token.
    func pushService(_ pushService: PushService, receivedDeviceToken token: String)
```

In `PushService.init` (after the `errorHandler` assignment, line 65):

```swift
        self.serviceProvider.deviceTokenUpdatedHandler = { [weak self] token in
            guard let self else { return }
            self.delegate?.pushService(self, receivedDeviceToken: token)
        }
```

In `OBAKit/PushNotifications/OBACloudPushService.swift`:

Add the property (after `errorHandler`, line 31):

```swift
    /// Called with the hex token on every successful APNs registration. Set by ``PushService`` during initialization.
    public var deviceTokenUpdatedHandler: PushManagerUserIDCallback?
```

In `didRegisterForRemoteNotifications(withDeviceToken:)` (line 105), after `Logger.info("APNs device token: \(token)")` add:

```swift
        deviceTokenUpdatedHandler?(token)
```

In `OBAKit/Orchestration/Application.swift`, in the `// MARK: - Push Notifications` section (after the `pushService` property, line 285), add:

```swift
    /// Keeps this device's APNs token registered with the current region's OBACloud server so
    /// agencies can send service-alert push notifications to it. See #1204.
    public private(set) lazy var pushRegistrationManager = PushRegistrationManager(
        obacoServiceProvider: { [weak self] in self?.obacoService },
        userDefaults: userDefaults,
        testDeviceProvider: { [weak self] in
            // "Test users only" audience: agencies preview an alert push against flagged
            // devices before sending it to everyone. Debug builds always qualify; release
            // builds qualify via the hidden Debug Mode setting.
            #if DEBUG
            return true
            #else
            return self?.userDataStore.debugMode ?? false
            #endif
        },
        currentRegionIdentifierProvider: { [weak self] in self?.currentRegionIdentifier }
    )
```

And add the new delegate method next to the other `PushServiceDelegate` methods (after `pushService(_:received:)`, line 318):

```swift
    public func pushService(_ pushService: PushService, receivedDeviceToken token: String) {
        pushRegistrationManager.updateDeviceToken(token)
        Task { await pushRegistrationManager.registerIfNeeded() }
    }
```

**Note:** `Application` also implements `pushService(_:receivedDonationPrompt:)` somewhere below line 318 — placement next to the existing delegate methods is what matters, not the exact line. If a release-build warning appears for the unused `self` capture in the `#if DEBUG` branch of `testDeviceProvider`, leave it — the release path uses it.

- [ ] **Step 4: Run the push notification test suites**

```bash
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests/OBACloudPushServiceTests -only-testing:OBAKitTests/PushServiceTests -only-testing:OBAKitTests/ApplicationTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: all three suites pass, including the two new tests.

- [ ] **Step 5: Commit**

```bash
git add OBAKit/PushNotifications/PushService.swift OBAKit/PushNotifications/OBACloudPushService.swift OBAKit/Orchestration/Application.swift OBAKitTests/PushNotifications/PushServiceTests.swift OBAKitTests/PushNotifications/OBACloudPushServiceTests.swift OBAKitTests/Application/ApplicationTests.swift
git commit -m "Thread APNs token updates to PushRegistrationManager via PushService (#1204)"
```

---

### Task 4: Lifecycle triggers, full verification

**Files:**
- Modify: `OBAKit/Orchestration/Application.swift` (`applicationDidBecomeActive` at line 428, `regionsService(_:updatedRegion:)` at line 658)

**Interfaces:**
- Consumes: `Application.pushRegistrationManager` (Task 3), `PushRegistrationManager.refreshRegistration()` / `.registerIfNeeded()` (Task 2).
- Produces: nothing new — final wiring.

**Testability note:** these triggers cannot be exercised by unit tests: `configurePushNotifications` early-returns under `#if targetEnvironment(simulator)`, so `pushService` is always nil in the simulator-hosted test suite. The behavior they invoke is fully covered by Task 2's manager tests; this task's verification is "full suite still green + lint clean," plus the on-device manual check below.

- [ ] **Step 1: Add the foreground trigger**

In `Application.applicationDidBecomeActive` (line 428), after `alertsStore.checkForUpdates()` (line 450), add:

```swift
        // Re-register the push token with OBACloud so the server's 180-day prune never drops
        // this device, and so locale changes propagate. The manager dedupes, so this only
        // hits the network when something changed or the last POST is a day old. Skipped on
        // the Simulator, where pushService is never configured.
        if pushService != nil {
            Task { await pushRegistrationManager.refreshRegistration() }
        }
```

- [ ] **Step 2: Add the region-change trigger**

In `Application.regionsService(_:updatedRegion:)` (line 658), at the end of the method body (after the analytics block), add:

```swift
        // By the time updatedRegion fires, willUpdateToRegion has already rebuilt
        // obacoService for the new region, so this registers the token there.
        Task { await pushRegistrationManager.registerIfNeeded() }
```

- [ ] **Step 3: Run the full unit test suite and SwiftLint**

```bash
set -o pipefail
xcodebuild build-for-testing -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
xcodebuild test-without-building -only-testing:OBAKitTests -project 'OBAKit.xcodeproj' -scheme 'App' -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
scripts/swiftlint.sh
```

Expected: full `OBAKitTests` suite passes with 0 failures; SwiftLint reports no new violations in the touched files.

- [ ] **Step 4: Commit**

```bash
git add OBAKit/Orchestration/Application.swift
git commit -m "Register push token with OBACloud on foreground and region change (#1204)"
```

- [ ] **Step 5: On-device manual verification (requires a physical device + an OBACloud admin)**

1. Run a Debug build on a device in a region whose `sidecarBaseURL` points at an OBACloud server; grant notification permission (the onboarding notifications step or alarm creation both trigger the prompt).
2. Confirm via server logs/console that `POST /api/v2/regions/{id}/push_registrations` arrived with `test_device=true` (Debug builds always flag) and the device's BCP-47 locale.
3. Background and re-foreground the app: no second POST (dedupe). Change the device language, re-foreground: a new POST with the new locale.
4. Switch regions to another sidecar-backed region: a POST against the new region's ID.
5. Have an OBACloud admin publish an alert with the "Test users only" audience — the device receives the push, and tapping it opens the app (plain title+body notification; no deep link expected).

Record the results of each check in the PR description.

---

## Self-Review

- **Spec coverage:** register on launch/foreground (Task 4 step 1 → `refreshRegistration`), on token rotation (Task 3: `didRegisterForRemoteNotifications` → handler → delegate → `registerIfNeeded`), on region change (Task 4 step 2). `test_device` sent on every call (Task 1, pinned by test). Locale sent as BCP-47 (Task 2 default provider). Authorization gate includes `.provisional`/`.ephemeral` (tested). Unregister endpoint implemented + tested (Task 1) but intentionally unwired — no in-app opt-out exists today, matching the issue's conditional phrasing. 422/404/429 handling: 422 and 404 surface as `APIError` (tested); 429 surfaces as `requestFailure` and is made unlikely by dedupe + coalescing.
- **Independent plan review (2026-07-18):** verified against the codebase and an empirical Swift 6 typecheck of the concurrency patterns — no blockers. Rework applied: provisional/ephemeral gate, stale-region guard (`currentRegionIdentifierProvider`), concurrent-call coalescing, DELETE query-param confirmed against the obacloud Rails spec, factual comment fixes.
- **Type consistency:** `postPushRegistration(token:locale:testDevice:)`, `deletePushRegistration(token:)`, `regionID`, `updateDeviceToken(_:)`, `registerIfNeeded()`, `refreshRegistration()`, `deviceTokenUpdatedHandler`, and `pushService(_:receivedDeviceToken:)` are spelled identically at definition and every use site across Tasks 1–4.
