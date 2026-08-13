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
/// lets tokens age out of the server's inactivity prune. This manager registers proactively:
/// `Application` calls ``refreshRegistration()`` on every foreground, feeds rotated tokens in
/// via ``updateDeviceToken(_:)`` + ``registerIfNeeded()``, and calls ``registerIfNeeded()``
/// again after a region change.
///
/// The last successful registration (token, region, locale, test-device flag, timestamp) is
/// persisted to user defaults; an unchanged registration is re-POSTed only after
/// ``refreshInterval``, keeping routine traffic to roughly one POST per day while still
/// refreshing the server's last-seen record ahead of its inactivity prune (failed POSTs retry
/// on the next trigger).
@MainActor
public final class PushRegistrationManager {

    public typealias AuthorizationStatusProvider = @Sendable () async -> UNAuthorizationStatus

    /// The inputs that determine whether a new POST is needed, plus when the last one happened.
    private struct Registration: Codable {
        let token: String
        let regionID: RegionIdentifier
        let locale: String
        let testDevice: Bool
        let description: String?
        let registeredAt: Date

        /// Equivalence over everything except `registeredAt` — age is checked separately.
        func isEquivalent(to other: Registration) -> Bool {
            token == other.token &&
            regionID == other.regionID &&
            locale == other.locale &&
            testDevice == other.testDevice &&
            description == other.description
        }
    }

    /// Re-POST an otherwise-unchanged registration this often so the server's 180-day
    /// `last_seen_at` prune never drops this device.
    nonisolated public static let refreshInterval: TimeInterval = 60 * 60 * 24

    nonisolated static let lastRegistrationUserDefaultsKey = "PushRegistrationManager.lastRegistration"

    /// Canonical key lives in OBAKitCore so `AgencyAlertsStore.shouldDisplayTestAlerts`
    /// can read the same value; this alias keeps existing call sites working.
    nonisolated static let testDeviceDescriptionDefaultsKey = AgencyAlertsStore.UserDefaultKeys.testDeviceDescription

    private let obacoServiceProvider: () -> ObacoAPIService?
    private let userDefaults: UserDefaults
    private let testDeviceProvider: () -> Bool
    /// Human-readable name identifying this test device to OBACloud admins. The server
    /// requires it for `test_device=true` registrations; without one the device registers
    /// as a regular device.
    private let testDeviceDescriptionProvider: () -> String?
    private let currentRegionIdentifierProvider: () -> RegionIdentifier?
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let localeProvider: () -> String
    private let dateProvider: () -> Date
    private let requestRemoteNotificationsRegistration: () -> Void
    /// Receives non-transient registration failures for remote error reporting. Injectable; defaults to a no-op.
    private let errorReporter: (Error) -> Void

    private var deviceToken: String?

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
    ///   - testDeviceDescriptionProvider: Human-readable name identifying this test device to
    ///     OBACloud admins. The server requires it for `test_device=true` registrations;
    ///     without one the device registers as a regular device.
    ///   - currentRegionIdentifierProvider: The user's current region. Guards against the
    ///     stale-`obacoService` case: switching to a region without a sidecar leaves the old
    ///     region's service in place, and we must never register against a region the user left.
    ///   - authorizationStatusProvider: Injectable for tests; defaults to the real
    ///     notification-center authorization status.
    ///   - localeProvider: Injectable for tests; defaults to the device's BCP-47 identifier.
    ///   - dateProvider: Injectable for tests; defaults to `Date()`.
    ///   - requestRemoteNotificationsRegistration: Injectable for tests; defaults to
    ///     `UIApplication.shared.registerForRemoteNotifications()`.
    ///   - errorReporter: Receives non-transient registration failures for remote error
    ///     reporting. Injectable; defaults to a no-op.
    public init(
        obacoServiceProvider: @escaping () -> ObacoAPIService?,
        userDefaults: UserDefaults,
        testDeviceProvider: @escaping () -> Bool,
        testDeviceDescriptionProvider: @escaping () -> String? = { nil },
        currentRegionIdentifierProvider: @escaping () -> RegionIdentifier?,
        authorizationStatusProvider: @escaping AuthorizationStatusProvider = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        localeProvider: @escaping () -> String = { Locale.current.identifier(.bcp47) },
        dateProvider: @escaping () -> Date = { Date() },
        requestRemoteNotificationsRegistration: @escaping () -> Void = {
            UIApplication.shared.registerForRemoteNotifications()
        },
        errorReporter: @escaping (Error) -> Void = { _ in }
    ) {
        self.obacoServiceProvider = obacoServiceProvider
        self.userDefaults = userDefaults
        self.testDeviceProvider = testDeviceProvider
        self.testDeviceDescriptionProvider = testDeviceDescriptionProvider
        self.currentRegionIdentifierProvider = currentRegionIdentifierProvider
        self.authorizationStatusProvider = authorizationStatusProvider
        self.localeProvider = localeProvider
        self.dateProvider = dateProvider
        self.requestRemoteNotificationsRegistration = requestRemoteNotificationsRegistration
        self.errorReporter = errorReporter
    }

    /// Stores the latest hex-encoded APNs token. Side-effect free — follow with
    /// ``registerIfNeeded()``. Called from the push provider's token callback, which fires on
    /// every `registerForRemoteNotifications()` including token rotations.
    public func updateDeviceToken(_ token: String) {
        guard !token.isEmpty else { return }
        deviceToken = token
    }

    /// Asks the OS for a (possibly rotated) device token and registers whatever token is
    /// already known. Call on every app foreground: callers are expected to route the
    /// resulting token callback back through ``updateDeviceToken(_:)`` + ``registerIfNeeded()``,
    /// so a rotated token is registered as soon as APNs delivers it. No-ops unless notification
    /// permission is granted.
    public func refreshRegistration() async {
        guard await isAuthorized() else { return }
        requestRemoteNotificationsRegistration()
        await registerIfNeeded()
    }

    /// POSTs the current token to the current region's Obaco server — but only if the token,
    /// region, locale, or test-device flag changed since the last successful POST, or that
    /// POST is older than ``refreshInterval``. No-ops without a token, an Obaco service
    /// matching the current region, or notification permission. Concurrent calls coalesce: on
    /// the first foreground after a permission grant, the becomeActive trigger and the APNs
    /// token callback can overlap, and only one POST should result.
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
        guard let deviceToken, let obacoService = obacoServiceProvider() else { return }

        // Switching to a region without a sidecar leaves the previous region's service in
        // place (CoreApplication.refreshObacoService early-returns) — never register
        // against a region the user left.
        guard obacoService.regionID == currentRegionIdentifierProvider() else {
            Logger.info("Skipping push registration: service region \(obacoService.regionID) is not the current region.")
            return
        }

        guard await isAuthorized() else { return }

        let trimmedDescription = testDeviceDescriptionProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (trimmedDescription?.isEmpty ?? true) ? nil : trimmedDescription
        // The server rejects test_device registrations without a description, so a test
        // device that hasn't been named yet registers as a regular device instead of
        // POSTing a guaranteed 422.
        let testDevice = testDeviceProvider() && description != nil

        let candidate = Registration(
            token: deviceToken,
            regionID: obacoService.regionID,
            locale: localeProvider(),
            testDevice: testDevice,
            description: testDevice ? description : nil,
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
                testDevice: candidate.testDevice,
                description: candidate.description)
            lastRegistration = candidate
            Logger.info("Registered push token with region \(candidate.regionID) (locale \(candidate.locale), testDevice \(candidate.testDevice)).")
        } catch is CancellationError {
            // Backgrounding mid-POST; the next trigger retries. Not a failure worth logging.
        } catch {
            // Leave `lastRegistration` untouched so the next trigger retries. Server-side
            // rejections are reported remotely: registrations are the server's only audience
            // source, so a systematic failure (fleet-wide 422s) must not be invisible.
            Logger.error("Push registration failed: \(error)")
            if case APIError.requestFailure = error {
                errorReporter(error)
            }
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
            do {
                return try userDefaults.decodeUserDefaultsObjects(type: Registration.self, key: Self.lastRegistrationUserDefaultsKey)
            } catch {
                // Schema drift degrades safely to "never registered" — the next POST is an
                // idempotent upsert — but leave a breadcrumb for the mystery re-POST.
                Logger.warn("Discarding undecodable push registration state: \(error)")
                return nil
            }
        }
        set {
            guard let newValue else {
                userDefaults.removeObject(forKey: Self.lastRegistrationUserDefaultsKey)
                return
            }
            try? userDefaults.encodeUserDefaultsObjects(newValue, key: Self.lastRegistrationUserDefaultsKey)
        }
    }
}
