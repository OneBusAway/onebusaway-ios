//
//  PushRegistrationManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UserNotifications
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `PushRegistrationManager` (issue #1204): keeping the device's APNs token
/// registered with the current region's OBACloud server — deduplicated, daily-refreshed,
/// and gated on notification authorization.
@MainActor
@Suite(.serialized)
final class PushRegistrationManagerTests: OBATestCase {

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

    override init() async throws {
        try await super.init()

        controls = Controls()
        dataLoader = MockDataLoader(testName: name)
        currentService = buildObacoService(dataLoader: dataLoader)
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    /// Mocks the `POST /push_registrations` response. Installed per-test rather than in
    /// `init()` because `MockDataLoader` matching is first-added-wins and the
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
            // Explicitly `@MainActor`: unlike the other providers, which inherit
            // the manager's isolation, AuthorizationStatusProvider is declared
            // `@Sendable`, so this closure is nonisolated by default and could
            // not touch main-actor-isolated `Controls`.
            authorizationStatusProvider: { @MainActor in
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

    @Test func `Register if needed posts token once`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 1)

        // Nothing changed: an immediate second call must not hit the network again.
        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 1)
    }

    @Test func `Register if needed without token does nothing`() async {
        let manager = makeManager()
        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 0)
    }

    @Test func `Register if needed without authorization does nothing`() async {
        controls.authorizationStatus = .denied
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 0)
    }

    /// Provisionally-authorized users receive quiet notifications — they count as opted in.
    @Test func `Register if needed registers with provisional authorization`() async {
        controls.authorizationStatus = .provisional
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 1)
    }

    /// `CoreApplication.refreshObacoService()` leaves the previous region's service in place
    /// when the user switches to a region without a sidecar — never register against a region
    /// the user has left.
    @Test func `Register if needed skips when obaco service region is stale`() async {
        controls.currentRegionID = 99
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 0)
    }

    @Test func `Register if needed without obaco service does nothing`() async {
        currentService = nil
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 0)
    }

    // MARK: - Re-registration triggers

    @Test func `Register if needed reposts when token rotates`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        manager.updateDeviceToken("cafed00d")
        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 2)
    }

    @Test func `Register if needed reposts when locale changes`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.locale = "es-MX"
        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 2)
    }

    @Test func `Register if needed reposts when test device flag changes`() async {
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

        #expect(registrationRequestCount == 2)
    }

    /// The server rejects `test_device=true` without a `description` — a test device that
    /// hasn't been named yet must register as a regular device rather than POST a
    /// guaranteed 422.
    @Test func `Register if needed downgrades test device without description`() async {
        let capture = mockRegistrationResponseCapturingBody()
        controls.testDevice = true
        controls.testDeviceDescription = nil
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 1)
        let body = try? #require(capture.bodies.first)
        #expect(capture.bodies.count == 1)
        #expect(body?.contains("test_device=false") ?? false, "Body: \(String(describing: body))")
        #expect(!(body?.contains("description=") ?? true), "Body: \(String(describing: body))")
    }

    /// A changed description is a real change to the wire payload (it identifies the device
    /// to admins), so it must trigger a re-POST even though token/region/locale/testDevice
    /// are unchanged.
    @Test func `Register if needed reposts when description changes`() async {
        mockRegistrationResponse()
        controls.testDevice = true
        controls.testDeviceDescription = "A"
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.testDeviceDescription = "B"
        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 2)
    }

    @Test func `Register if needed reposts when region changes`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 1)

        // Same host, different region — mirrors CoreApplication rebuilding obacoService
        // after a region switch.
        let config = APIServiceConfiguration(baseURL: obacoURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: 2)
        currentService = ObacoAPIService(regionID: 2, delegate: nil, configuration: config, dataLoader: dataLoader)
        controls.currentRegionID = 2

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 2)
        #expect(dataLoader.recordedRequestURLs.contains { $0.path.hasSuffix("/regions/2/push_registrations") })
    }

    /// The server prunes tokens it hasn't seen recently; an unchanged registration is
    /// therefore re-POSTed once its age exceeds the refresh interval.
    @Test func `Register if needed reposts when stale`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        controls.now = controls.now.addingTimeInterval(PushRegistrationManager.refreshInterval + 60)
        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 2)
    }

    /// Dedupe state persists across manager instances (i.e., app launches).
    @Test func `Register if needed dedupe survives relaunch`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()

        let relaunched = makeManager()
        relaunched.updateDeviceToken("01abff007f")
        await relaunched.registerIfNeeded()

        #expect(registrationRequestCount == 1)
    }

    // MARK: - Failure handling

    /// A failed POST must not be recorded as a successful registration — the next call retries.
    @Test func `Register if needed does not persist on server error`() async {
        mockRegistrationResponse(statusCode: 422)

        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")
        await manager.registerIfNeeded()
        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 2, "Expected a retry because the first POST failed")
    }

    // MARK: - Coalescing

    /// On the first foreground after a permission grant, the becomeActive trigger and the
    /// APNs token callback can both call `registerIfNeeded()` before either finishes — the
    /// second caller must coalesce into the first instead of double-POSTing.
    @Test func `Register if needed coalesces concurrent calls`() async {
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

        #expect(registrationRequestCount == 1)
    }

    // MARK: - refreshRegistration

    @Test func `Refresh registration requests APNs registration when authorized`() async {
        let manager = makeManager()
        await manager.refreshRegistration()
        #expect(controls.remoteRegistrationRequests == 1)
    }

    @Test func `Refresh registration skips APNs registration when denied`() async {
        controls.authorizationStatus = .denied
        let manager = makeManager()
        await manager.refreshRegistration()
        #expect(controls.remoteRegistrationRequests == 0)
        #expect(registrationRequestCount == 0)
    }

    /// The foreground refresh must POST the already-known token itself — APNs is not
    /// guaranteed to re-deliver a token callback, so this is what keeps `last_seen_at` fresh.
    @Test func `Refresh registration posts already known token`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.refreshRegistration()

        #expect(registrationRequestCount == 1)
    }

    /// A token that rotates while a registration is in flight must be registered by the
    /// coalescing loop's follow-up pass — and recorded, so it isn't re-POSTed again.
    @Test func `Register if needed registers rotated token arriving mid flight`() async {
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

        #expect(registrationRequestCount == 2, "Expected the follow-up pass to register the rotated token")

        await manager.registerIfNeeded()
        #expect(registrationRequestCount == 2, "Expected the rotated token to be recorded as registered")
    }

    /// Corrupted persisted state must degrade to "never registered", not crash or skip.
    @Test func `Register if needed recovers from corrupted persisted state`() async {
        defaults.set("not a plist blob", forKey: PushRegistrationManager.lastRegistrationUserDefaultsKey)
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 1)
    }

    @Test func `Update device token ignores empty token`() async {
        mockRegistrationResponse()
        let manager = makeManager()
        manager.updateDeviceToken("")

        await manager.registerIfNeeded()

        #expect(registrationRequestCount == 0)
    }

    /// Server rejections reach the injected error reporter (Crashlytics in production);
    /// registrations are the server's only audience source, so fleet-wide failures must
    /// be observable somewhere.
    @Test func `Register if needed reports server rejections to error reporter`() async {
        mockRegistrationResponse(statusCode: 422)
        let manager = makeManager()
        manager.updateDeviceToken("01abff007f")

        await manager.registerIfNeeded()

        #expect(controls.reportedErrors.count == 1)
    }
}
