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
        var testDeviceDescription: String?
        var currentRegionID: Int? = 1
        var now = Date(timeIntervalSince1970: 1_752_800_000)
        var remoteRegistrationRequests = 0
        /// When true, the next auth-status check parks on `authGate` until the test resumes it —
        /// lets the coalescing test hold a registration mid-flight deterministically.
        var holdNextAuthCheck = false
        var authGate: CheckedContinuation<Void, Never>?
        var reportedErrors: [Error] = []
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

    /// Captures the body of the request the service actually put on the wire, so the
    /// downgrade/description tests can inspect what was (or wasn't) sent, not just how many
    /// times it was sent.
    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var bodies: [String] = []
    }

    private func mockRegistrationResponseCapturingBody(statusCode: Int = 204) -> RequestCapture {
        let capture = RequestCapture()
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/push_registrations") ?? false else {
                return false
            }
            if let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
                capture.bodies.append(body)
            }
            return true
        }
        return capture
    }

    private func makeManager() -> PushRegistrationManager {
        let controls = self.controls!
        return PushRegistrationManager(
            obacoServiceProvider: { [weak self] in self?.currentService },
            userDefaults: defaults,
            testDeviceProvider: { controls.testDevice },
            testDeviceDescriptionProvider: { controls.testDeviceDescription },
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
            requestRemoteNotificationsRegistration: { controls.remoteRegistrationRequests += 1 },
            errorReporter: { controls.reportedErrors.append($0) }
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

        // Setting `testDevice` alone doesn't change the wire value — without a description
        // the candidate downgrades to a regular device, same as before. Naming the device is
        // what actually flips `test_device` on the wire.
        controls.testDevice = true
        controls.testDeviceDescription = "Aarons iPhone"
        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 2)
    }

    /// The server rejects `test_device=true` without a `description` — a test device that
    /// hasn't been named yet must register as a regular device rather than POST a
    /// guaranteed 422.
    func test_registerIfNeeded_downgradesTestDeviceWithoutDescription() async {
        let capture = mockRegistrationResponseCapturingBody()
        controls.testDevice = true
        controls.testDeviceDescription = nil
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 1)
        let body = try? XCTUnwrap(capture.bodies.first)
        XCTAssertEqual(capture.bodies.count, 1)
        XCTAssertTrue(body?.contains("test_device=false") ?? false, "Body: \(String(describing: body))")
        XCTAssertFalse(body?.contains("description=") ?? true, "Body: \(String(describing: body))")
    }

    /// A changed description is a real change to the wire payload (it identifies the device
    /// to admins), so it must trigger a re-POST even though token/region/locale/testDevice
    /// are unchanged.
    func test_registerIfNeeded_repostsWhenDescriptionChanges() async {
        mockRegistrationResponse()
        controls.testDevice = true
        controls.testDeviceDescription = "A"
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.testDeviceDescription = "B"
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

    /// The server prunes tokens it hasn't seen recently; an unchanged registration is
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

    /// The foreground refresh must POST the already-known token itself — APNs is not
    /// guaranteed to re-deliver a token callback, so this is what keeps `last_seen_at` fresh.
    func test_refreshRegistration_postsAlreadyKnownToken() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.refreshRegistration()

        XCTAssertEqual(registrationRequestCount, 1)
    }

    /// A token that rotates while a registration is in flight must be registered by the
    /// coalescing loop's follow-up pass — and recorded, so it isn't re-POSTed again.
    func test_registerIfNeeded_registersRotatedTokenArrivingMidFlight() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        controls.holdNextAuthCheck = true
        let first = Task { await manager.registerIfNeeded() }
        while controls.authGate == nil { await Task.yield() }

        manager.updateDeviceToken("cafed00d")
        await manager.registerIfNeeded()

        controls.authGate?.resume()
        controls.authGate = nil
        _ = await first.value

        XCTAssertEqual(registrationRequestCount, 2, "Expected the follow-up pass to register the rotated token")

        await manager.registerIfNeeded()
        XCTAssertEqual(registrationRequestCount, 2, "Expected the rotated token to be recorded as registered")
    }

    /// Corrupted persisted state must degrade to "never registered", not crash or skip.
    func test_registerIfNeeded_recoversFromCorruptedPersistedState() async {
        defaults.set("not a plist blob", forKey: PushRegistrationManager.lastRegistrationUserDefaultsKey)
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 1)
    }

    func test_updateDeviceToken_ignoresEmptyToken() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("")

        await manager.registerIfNeeded()

        XCTAssertEqual(registrationRequestCount, 0)
    }

    /// Server rejections reach the injected error reporter (Crashlytics in production);
    /// registrations are the server's only audience source, so fleet-wide failures must
    /// be observable somewhere.
    func test_registerIfNeeded_reportsServerRejectionsToErrorReporter() async {
        mockRegistrationResponse(statusCode: 422)
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        XCTAssertEqual(controls.reportedErrors.count, 1)
    }
}
