//
//  GetOffAlertManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import UserNotifications
import OBAKitCore

// MARK: - Activation Result

/// The outcome of a request to arm a get-off alert on a specific stop.
///
/// Every non-`.activated` case is a condition the caller must surface: a silent
/// failure looks identical to a successfully armed alert from the rider's
/// perspective until they miss their stop.
public enum GetOffAlertActivationResult: Equatable {
    /// Stored and armed at the requested radius.
    case activated(GetOffAlert)

    /// Stored and armed, but at a smaller radius than asked because the device
    /// will not monitor one that large. The notification fires closer to the stop.
    case activatedWithClampedRadius(GetOffAlert, requested: CLLocationDistance, monitored: CLLocationDistance)

    /// Nothing stored: the geofence requires `.authorizedAlways` and the app
    /// holds the status carried here.
    case needsLocationAuthorization(CLAuthorizationStatus)

    /// Nothing stored: the notification couldn't be delivered because notification
    /// permission hasn't been granted yet (`.notDetermined`) or was denied.
    case needsNotificationAuthorization(UNAuthorizationStatus)

    /// Nothing stored: a get-off alert for this trip and stop is already active.
    case alreadyActive(GetOffAlert)

    /// Nothing stored: the app already monitors the OS-imposed geofence cap.
    case regionLimitReached(limit: Int)
}

// MARK: - Manager

/// Owns the in-trip stop-approach alerts a rider has set.
///
/// The lifecycle mirrors `ProximityAlertManager` exactly:
///
/// - Alerts are stored in `UserDataStore` and armed as `CLCircularRegion`s via
///   `LocationService`, using its own region-identifier prefix so the two
///   features' regions never collide.
/// - Geofence events arrive via `LocationServiceDelegate`. On entry the manager
///   delivers an immediate local notification and cancels the alert (one-shot).
/// - `reconcileMonitoredRegions()` brings the two stores of truth back in sync
///   at construction, on any store change, on foreground, and on authorization
///   change — covering every path that can leave them out of step.
/// - The manager must be constructed eagerly at app launch. A geofence crossing
///   can relaunch a terminated app; Core Location delivers the event to whatever
///   `LocationService` delegates exist by the time launch completes.
@MainActor
public final class GetOffAlertManager: NSObject, LocationServiceDelegate {

    // MARK: - Types

    /// Injectable notification-permission check. Mirrors `ProximityAlertManager`.
    public typealias AuthorizationStatusProvider = @Sendable () async -> UNAuthorizationStatus

    /// Returns the OBA region identifier at the moment an alert is created.
    public typealias RegionIDProvider = @MainActor () -> Int?

    /// Hands a `UNNotificationRequest` to the system. Completion-handler form —
    /// not async — because this runs during a Core Location background launch
    /// where the process has seconds to live and a Task might never be scheduled.
    public typealias NotificationScheduler = (UNNotificationRequest, @escaping @Sendable (Error?) -> Void) -> Void

    // MARK: - Constants

    /// `userInfo` key carrying the stop ID when the notification is tapped.
    static let notificationStopIDKey = "get_off_alert_stop_id"

    /// `userInfo` key carrying the region ID (optional — absent on alerts
    /// persisted before the field existed).
    static let notificationRegionIDKey = "get_off_alert_region_id"

    private static let notificationIdentifierPrefix = "oba.get-off-notification."

    // MARK: - Dependencies

    private let locationService: LocationService
    private let userDataStore: UserDataStore
    private let regionIDProvider: RegionIDProvider
    private let notificationCenter: NotificationCenter
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let scheduleNotification: NotificationScheduler

    /// Re-entrance guard. The store notifications that reconciliation posts
    /// (expired-alert deletions) must not trigger a second pass against
    /// half-updated state.
    private var isReconciling = false

    // MARK: - Init

    public init(
        locationService: LocationService,
        userDataStore: UserDataStore,
        regionIDProvider: @escaping RegionIDProvider = { nil },
        notificationCenter: NotificationCenter = .default,
        authorizationStatusProvider: @escaping AuthorizationStatusProvider = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        scheduleNotification: @escaping NotificationScheduler = { request, completion in
            UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
        }
    ) {
        self.locationService = locationService
        self.userDataStore = userDataStore
        self.regionIDProvider = regionIDProvider
        self.notificationCenter = notificationCenter
        self.authorizationStatusProvider = authorizationStatusProvider
        self.scheduleNotification = scheduleNotification

        super.init()

        locationService.addDelegate(self)

        // Selector form — not the block form — so there is nothing to unregister
        // in `deinit`. Mirrors `ProximityAlertManager`'s reasoning.
        notificationCenter.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: .getOffAlertsDidChange,
            object: nil
        )

        reconcileMonitoredRegions()
    }

    @objc private func storeDidChange() {
        reconcileMonitoredRegions()
    }

    // MARK: - Reading

    /// All stored alerts, expired ones included. Expiry is `reconcileMonitoredRegions`'s job.
    public var alerts: [GetOffAlert] {
        userDataStore.getOffAlerts
    }

    /// The unexpired alert for the given trip and stop, or nil.
    public func activeAlert(tripID: String, stopID: StopID) -> GetOffAlert? {
        userDataStore.getOffAlerts.first {
            $0.tripID == tripID && $0.stopID == stopID && !$0.isExpired
        }
    }

    /// Whether an unexpired alert is already set for the given trip and stop.
    public func hasActiveAlert(tripID: String, stopID: StopID) -> Bool {
        activeAlert(tripID: tripID, stopID: stopID) != nil
    }

    // MARK: - Creating

    /// Arms a get-off alert for `stop` on `tripID`.
    ///
    /// Nothing is stored unless the geofence actually arms, so the store can
    /// never hold an alert Core Location knows nothing about.
    public func createAlert(
        for stop: Stop,
        tripID: String,
        stopSequence: Int,
        radiusMeters: CLLocationDistance = GetOffAlert.defaultRadiusMeters
    ) async -> GetOffAlertActivationResult {
        guard locationService.isProximityMonitoringAuthorized else {
            return .needsLocationAuthorization(locationService.authorizationStatus)
        }

        let notificationStatus = await authorizationStatusProvider()
        guard Self.allowsNotificationDelivery(notificationStatus) else {
            return .needsNotificationAuthorization(notificationStatus)
        }

        if let existing = activeAlert(tripID: tripID, stopID: stop.id) {
            return .alreadyActive(existing)
        }

        let alert = GetOffAlert(
            stop: stop,
            tripID: tripID,
            stopSequence: stopSequence,
            radiusMeters: radiusMeters,
            regionID: regionIDProvider()
        )

        switch locationService.startMonitoringGetOffAlert(alert) {
        case .started:
            userDataStore.add(getOffAlert: alert)
            return .activated(alert)

        case .startedWithClampedRadius(let requested, let monitored):
            userDataStore.add(getOffAlert: alert)
            return .activatedWithClampedRadius(alert, requested: requested, monitored: monitored)

        case .insufficientAuthorization(let status):
            return .needsLocationAuthorization(status)

        case .regionLimitReached(let limit):
            return .regionLimitReached(limit: limit)
        }
    }

    // MARK: - Cancelling

    /// Disarms and removes a single alert.
    public func cancel(_ alert: GetOffAlert) {
        locationService.stopMonitoringGetOffAlert(alert)
        userDataStore.delete(getOffAlert: alert)
    }

    /// Cancels every alert associated with `tripID`.
    ///
    /// Call when the trip page disappears so a stale geofence never fires on a
    /// later, unrelated trip that happens to pass the same stop.
    public func cancelAlerts(forTripID tripID: String) {
        for alert in userDataStore.getOffAlerts where alert.tripID == tripID {
            locationService.stopMonitoringGetOffAlert(alert)
        }
        userDataStore.deleteGetOffAlerts(forTripID: tripID)
    }

    /// Disarms and removes every stored get-off alert.
    public func cancelAll() {
        locationService.stopMonitoringAllGetOffAlerts()
        userDataStore.deleteAllGetOffAlerts()
    }

    // MARK: - Reconciliation

    /// Brings Core Location's armed regions back in line with the stored alerts.
    ///
    /// Idempotent: re-arming an already-monitored alert replaces its region
    /// rather than consuming an extra slot.
    public func reconcileMonitoredRegions() {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        userDataStore.deleteExpiredGetOffAlerts()

        let alerts = userDataStore.getOffAlerts
        let storedIDs = Set(alerts.map(\.id))

        // Disarm orphaned regions first so their slots return to the budget
        // before the arming pass below.
        for orphanedID in locationService.monitoredGetOffAlertIDs.subtracting(storedIDs) {
            locationService.stopMonitoringGetOffAlertID(orphanedID)
            Logger.info("GetOffAlertManager: disarmed orphaned region for alert \(orphanedID).")
        }

        for alert in alerts {
            let result = locationService.startMonitoringGetOffAlert(alert)
            if !result.isMonitoring {
                Logger.warn("GetOffAlertManager: alert \(alert.id) for stop \(alert.stopID) not armed: \(result).")
            }
        }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, didEnterMonitoredRegion identifier: String) {
        guard let alertID = LocationService.getOffAlertID(forRegionIdentifier: identifier) else {
            return
        }

        guard let alert = userDataStore.getOffAlerts.first(where: { $0.id == alertID }) else {
            Logger.warn("GetOffAlertManager: entered region for alert \(alertID), no longer stored. Disarming.")
            locationService.stopMonitoringGetOffAlertID(alertID)
            return
        }

        guard !alert.isExpired else {
            Logger.info("GetOffAlertManager: alert \(alertID) fired after expiring. Discarding.")
            cancel(alert)
            return
        }

        deliverNotification(for: alert)
        cancel(alert)
    }

    public func locationService(
        _ service: LocationService,
        authorizationStatusChanged status: CLAuthorizationStatus
    ) {
        // Re-arm any alerts that couldn't arm before the user granted Always.
        guard service.isProximityMonitoringAuthorized else { return }
        reconcileMonitoredRegions()
    }

    public func locationService(
        _ service: LocationService,
        monitoringDidFailFor identifier: String?,
        error: Error,
        kind: RegionMonitoringFailureKind
    ) {
        // Ignore failures from other features' regions.
        if let identifier, !identifier.hasPrefix(LocationService.getOffAlertRegionPrefix) {
            return
        }

        guard !kind.isTransient else { return }

        guard let identifier,
              let alertID = LocationService.getOffAlertID(forRegionIdentifier: identifier) else {
            Logger.error("GetOffAlertManager: monitoring failed (\(kind)) without a region: \(error)")
            return
        }

        // The region is dead; return its slot. The alert stays in the store so
        // reconciliation gets one more chance to re-arm it.
        Logger.error("GetOffAlertManager: monitoring failed permanently (\(kind)) for alert \(alertID): \(error)")
        locationService.stopMonitoringGetOffAlertID(alertID)
    }

    // MARK: - Notification Delivery

    private func deliverNotification(for alert: GetOffAlert) {
        let content = UNMutableNotificationContent()
        content.title = OBALoc(
            "get_off_alert.notification.title",
            value: "Time to get off",
            comment: "Title of the notification shown when the rider is approaching the stop they set a get-off alert on."
        )
        content.body = String(
            format: OBALoc(
                "get_off_alert.notification.body_fmt",
                value: "Your stop, %@, is coming up.",
                comment: "Body of the get-off alert notification. %@ is the name of the rider's destination stop."
            ),
            alert.stopName
        )
        content.sound = .default

        var userInfo: [String: Any] = [Self.notificationStopIDKey: alert.stopID]
        if let regionID = alert.regionID {
            userInfo[Self.notificationRegionIDKey] = regionID
        }
        content.userInfo = userInfo

        let requestID = Self.notificationIdentifierPrefix + alert.id.uuidString
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)

        scheduleNotification(request) { error in
            if let error {
                Logger.error("GetOffAlertManager: failed to schedule notification for alert \(alert.id): \(error)")
            }
        }
    }

    // MARK: - Helpers

    private static func allowsNotificationDelivery(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
