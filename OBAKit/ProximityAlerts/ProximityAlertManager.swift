//
//  ProximityAlertManager.swift
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

/// The outcome of a rider's request for a proximity alert on a stop.
///
/// Everything other than `activated` is a condition the rider has to be told
/// about. A proximity alert is silent by design right up until it fires, so an
/// alert that never armed looks exactly like one that simply hasn't fired yet —
/// the rider finds out at the stop they meant to get off at.
public enum ProximityAlertActivationResult: Equatable {
    /// Stored and armed at the requested radius.
    case activated(ProximityAlert)

    /// Stored and armed, but at a smaller radius than requested, because this
    /// device will not monitor one that large. The alert will fire closer to the
    /// stop than the rider asked for.
    case activatedWithClampedRadius(ProximityAlert, requested: CLLocationDistance, monitored: CLLocationDistance)

    /// Nothing was stored: geofences only deliver in the background under
    /// `.authorizedAlways`, and the app holds the status carried here.
    case needsLocationAuthorization(CLAuthorizationStatus)

    /// Nothing was stored: the geofence would arm, but the notification it exists
    /// to show could never be delivered. `.notDetermined` means nobody has asked
    /// the rider yet; `.denied` means they have to be sent to Settings.
    case needsNotificationAuthorization(UNAuthorizationStatus)

    /// Nothing was stored: this stop already has an unexpired alert, handed back
    /// here. A second one would arm another geofence at the same coordinate, take
    /// another of the twenty region slots, and fire alongside the first.
    case alreadyActive(ProximityAlert)

    /// Nothing was stored: the app already monitors `limit` regions, which is all
    /// iOS allows. An existing alert has to go before another can arm.
    case regionLimitReached(limit: Int)
}

/// Owns the destination proximity alerts a rider has set: which ones are armed
/// with Core Location, what happens when one fires, and how the two are kept in
/// agreement.
///
/// Two stores of truth have to be reconciled here, and they drift apart in both
/// directions. Monitored regions live in Core Location, survive app termination,
/// and are the only thing that can wake the app in the background. The
/// `ProximityAlert` values that explain those regions live in `UserDataStore`,
/// expire 24 hours after they were created, and can be mutated by anything
/// holding the store. Neither side notices the other changing, so every entry
/// point funnels into ``reconcileMonitoredRegions()``.
///
/// This has to exist before launch finishes. A geofence crossing relaunches a
/// terminated app, and Core Location delivers the queued event to whatever
/// `LocationService` delegates exist by then — so `Application` builds this
/// eagerly in its initializer rather than lazily on first use, which on a
/// background launch would be never.
@MainActor
public final class ProximityAlertManager: NSObject, LocationServiceDelegate {

    /// Injectable for tests; defaults to the real notification-center status.
    /// Mirrors ``PushRegistrationManager/AuthorizationStatusProvider``.
    public typealias AuthorizationStatusProvider = @Sendable () async -> UNAuthorizationStatus

    /// Names the region the rider is in when they set an alert.
    ///
    /// A closure rather than a `RegionsService` dependency: this needs one integer
    /// at one moment, and taking the service would hand the manager a collaborator
    /// it has no other use for and every test a stand-in to build. `@MainActor`
    /// because the real one reads `RegionsService`, which is.
    public typealias RegionIDProvider = @MainActor () -> Int?

    /// Hands a notification request to the system.
    ///
    /// Deliberately the completion-handler form rather than the `async` one. The
    /// fire path runs during a Core Location background launch, where the process
    /// has seconds to live; this posts the request to the notification daemon on
    /// the spot instead of parking it in a `Task` the system may suspend the app
    /// before ever scheduling.
    public typealias NotificationScheduler = (UNNotificationRequest, @escaping @Sendable (Error?) -> Void) -> Void

    /// Key under which the fired alert's stop ID travels in the notification's
    /// `userInfo`, and the name `PushService` routes a tap on.
    static let notificationUserInfoKey = "proximity_alert"

    /// Key under which the region the alert was set in travels alongside
    /// ``notificationUserInfoKey``. Absent when the alert recorded none, which is
    /// what every alert stored before this field existed looks like.
    static let notificationRegionUserInfoKey = "proximity_alert_region"

    /// Namespaces the `UNNotificationRequest` identifier so a proximity
    /// notification can never collide with, or replace, one from another feature.
    static let notificationIdentifierPrefix = "oba.proximity-alert."

    private let locationService: LocationService
    private let userDataStore: UserDataStore
    private let regionIDProvider: RegionIDProvider
    private let notificationCenter: NotificationCenter
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let scheduleNotification: NotificationScheduler

    /// Guards against re-entering reconciliation through the store notifications
    /// that reconciliation itself provokes: reaping a single expired alert posts
    /// `.proximityAlertsDidChange`, which lands back here mid-pass and would run
    /// the whole comparison a second time against half-updated state.
    private var isReconciling = false

    /// - Parameters:
    ///   - locationService: Arms and disarms the geofences, and reports crossings.
    ///   - userDataStore: Persists the alerts the geofences stand for.
    ///   - regionIDProvider: Names the region an alert is being set in, recorded
    ///     on the alert so a tap on its notification opens the stop against the
    ///     region the rider actually set it in. Defaults to naming none, which
    ///     leaves the tap falling back to whichever region is current.
    ///   - notificationCenter: Carries `.proximityAlertsDidChange`. `UserDataStore`
    ///     posts to `.default`, so an injected center only sees store changes if
    ///     it is that same center.
    ///   - authorizationStatusProvider: Injectable for tests; defaults to the real
    ///     notification-center authorization status.
    ///   - scheduleNotification: Injectable for tests; defaults to
    ///     `UNUserNotificationCenter.current().add(_:withCompletionHandler:)`.
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

        // The selector form, not `addObserver(forName:object:queue:using:)`. The
        // block form hands back a token that has to be removed in `deinit`, and
        // this object's last release lands wherever `Application`'s does — which
        // is a background cooperative thread often enough to matter. A `deinit`
        // that has to touch main-actor state to unregister traps there. Selector
        // observers are held weakly and dropped by the center on dealloc, so
        // there is nothing to unregister and no `deinit` to isolate.
        notificationCenter.addObserver(
            self,
            selector: #selector(proximityAlertsDidChange),
            name: .proximityAlertsDidChange,
            object: nil
        )

        reconcileMonitoredRegions()
    }

    /// Delivered synchronously on whichever thread mutated the store. Every
    /// mutation the app makes runs on the main actor — the same assumption
    /// `MapViewController` makes of `.bookmarksDidChange`, from the same store.
    @objc private func proximityAlertsDidChange() {
        reconcileMonitoredRegions()
    }

    // MARK: - Reading Alerts

    /// The alerts the rider has set, expired ones included — reaping is
    /// ``reconcileMonitoredRegions()``'s job, and it has not necessarily run since
    /// the last one aged out.
    public var proximityAlerts: [ProximityAlert] {
        userDataStore.proximityAlerts
    }

    /// The unexpired alert set on `stopID`, if there is one.
    public func activeAlert(for stopID: StopID) -> ProximityAlert? {
        userDataStore.proximityAlerts.first { $0.stopID == stopID && !$0.isExpired }
    }

    // MARK: - Creating and Cancelling

    /// Stores and arms an alert on `stop`, or explains why it couldn't.
    ///
    /// Nothing is stored unless the geofence actually armed. The reverse order —
    /// persist, then try to monitor — is what leaves the app holding an alert the
    /// rider believes in and Core Location knows nothing about.
    public func createProximityAlert(
        for stop: Stop,
        radiusMeters: CLLocationDistance = ProximityAlert.defaultRadiusMeters
    ) async -> ProximityAlertActivationResult {
        // Checked ahead of arming rather than after, so a refusal costs no region
        // slot and leaves no half-created state to unwind.
        guard locationService.isProximityMonitoringAuthorized else {
            return .needsLocationAuthorization(locationService.authorizationStatus)
        }

        // Unlike departure alarms — where `pushID()` downstream triggers the
        // first-time system prompt, so `.notDetermined` is safe to fall through —
        // nothing later in this path prompts. `UNUserNotificationCenter.add` on an
        // undetermined app neither asks nor delivers, so both statuses are dead
        // ends here and the caller has to resolve them.
        let notificationStatus = await authorizationStatusProvider()
        guard Self.allowsNotificationDelivery(notificationStatus) else {
            return .needsNotificationAuthorization(notificationStatus)
        }

        // A second alert on this stop would arm a second geofence at the same
        // coordinate, hold another of the twenty slots the cap guard counts, and
        // fire alongside the first. `activeAlert(for:)` ignores expired alerts, so
        // a stale one does not block a new one.
        //
        // Checked after the authorization guards rather than before them: a
        // downgrade from Always neither disarms nor deletes — see
        // `locationService(_:authorizationStatusChanged:)`, which logs and returns
        // — so a stored alert can look healthy here while no longer able to
        // deliver. That rider needs `.needsLocationAuthorization`, which is both
        // actionable and the explanation for why the alert they already have went
        // quiet, rather than being told they already have one.
        if let existing = activeAlert(for: stop.id) {
            return .alreadyActive(existing)
        }

        let alert = ProximityAlert(stop: stop, radiusMeters: radiusMeters, regionID: regionIDProvider())

        switch locationService.startMonitoringProximity(for: alert) {
        case .started:
            userDataStore.add(proximityAlert: alert)
            return .activated(alert)
        case .startedWithClampedRadius(let requested, let monitored):
            userDataStore.add(proximityAlert: alert)
            return .activatedWithClampedRadius(alert, requested: requested, monitored: monitored)
        case .insufficientAuthorization(let status):
            return .needsLocationAuthorization(status)
        case .regionLimitReached(let limit):
            return .regionLimitReached(limit: limit)
        }
    }

    /// Disarms and forgets a single alert.
    public func cancelProximityAlert(_ alert: ProximityAlert) {
        locationService.stopMonitoringProximity(for: alert)
        userDataStore.delete(proximityAlert: alert)
    }

    /// Disarms and forgets every alert, leaving regions the app monitors for
    /// other reasons alone.
    public func cancelAllProximityAlerts() {
        locationService.stopMonitoringAllProximityAlerts()
        userDataStore.deleteAllProximityAlerts()
    }

    // MARK: - Reconciliation

    /// Brings Core Location's armed regions back in line with the stored alerts.
    ///
    /// Called on every occasion the two can disagree — construction (which on a
    /// background launch is the app's only chance to re-arm), any change to the
    /// store, a return to the foreground, and the grant of Always authorization.
    /// They all repair the same disagreement, so they all run the same comparison
    /// rather than each patching the case it happens to know about.
    ///
    /// Idempotent: arming an alert that is already monitored replaces its region
    /// instead of adding one, so extra calls cost nothing.
    public func reconcileMonitoredRegions() {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        userDataStore.deleteExpiredProximityAlerts()

        let alerts = userDataStore.proximityAlerts
        let storedIDs = Set(alerts.map(\.id))

        // Regions whose alert is gone — deleted while this process wasn't running,
        // or reaped as expired a line ago. Nothing would be able to explain them
        // if they fired. Disarming them first also returns their slots to the
        // twenty-region budget before the arming pass below spends it.
        for orphanedID in locationService.monitoredProximityAlertIDs.subtracting(storedIDs) {
            Logger.info("Disarming proximity region \(orphanedID), whose alert is no longer stored.")
            locationService.stopMonitoringProximityAlert(id: orphanedID)
        }

        for alert in alerts {
            let result = locationService.startMonitoringProximity(for: alert)
            guard !result.isMonitoring else { continue }
            // `startMonitoringProximity` logs the specifics. This says which alert
            // the rider is going to be let down by, which that call cannot know is
            // interesting until someone is tracking a set of them.
            Logger.warn("Proximity alert \(alert.id) for stop \(alert.stopID) is stored but not armed: \(result).")
        }
    }

    // MARK: - LocationServiceDelegate

    public func locationService(_ service: LocationService, didEnterMonitoredRegion identifier: String) {
        guard let alertID = LocationService.proximityAlertID(forRegionIdentifier: identifier) else {
            Logger.error("Entered proximity region \(identifier), whose identifier carries no alert ID. Ignoring.")
            return
        }

        guard let alert = userDataStore.proximityAlerts.first(where: { $0.id == alertID }) else {
            // Armed with nothing left to explain it: the alert was deleted by a
            // process that has since been replaced, and no reconciliation has run
            // in this one yet. Reap it rather than let it fire again tomorrow.
            Logger.warn("Entered proximity region for alert \(alertID), which is no longer stored. Disarming it.")
            service.stopMonitoringProximityAlert(id: alertID)
            return
        }

        // Set for a trip that ended a day or more ago. Waking the rider now would
        // be worse than never firing at all, and this is the last line of defense:
        // the region stays armed until something reconciles, which on a background
        // launch happens moments before this callback, not after it.
        guard !alert.isExpired else {
            Logger.info("Proximity alert \(alertID) crossed its geofence after expiring. Discarding it.")
            cancelProximityAlert(alert)
            return
        }

        deliverArrivalNotification(for: alert)

        // One-shot. The rider set this for one trip; a geofence left armed fires
        // again on tomorrow's commute past the same stop.
        cancelProximityAlert(alert)
    }

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        // Region monitoring has no self-healing re-arm of its own: an alert that
        // could not arm under When In Use stays dead after the rider grants Always
        // in Settings, because nothing asks Core Location a second time. This is
        // the only place that gap closes.
        guard service.isProximityMonitoringAuthorized else {
            // Not an error — When In Use is an ordinary state, and during
            // onboarding there is nothing armed to lose. But when alerts *are*
            // armed this is the moment they may quietly stop being deliverable,
            // and nothing else records it: Core Location reports nothing when a
            // region that is already monitored loses the authorization that let
            // it deliver in the background.
            let armedCount = service.monitoredProximityAlertIDs.count
            if armedCount > 0 {
                Logger.warn("Location authorization is now \(status) with \(armedCount) proximity alert(s) armed; they may no longer deliver in the background.")
            }
            return
        }
        reconcileMonitoredRegions()
    }

    public func locationService(_ service: LocationService, monitoringDidFailFor identifier: String?, error: Error, kind: RegionMonitoringFailureKind) {
        guard !kind.isTransient else {
            // The OS deferred the request instead of refusing it, and will get to
            // it on its own. Re-arming now would race that retry.
            Logger.info("Proximity monitoring for \(identifier ?? "an unattributed region") was delayed; leaving it armed.")
            return
        }

        guard let identifier, let alertID = LocationService.proximityAlertID(forRegionIdentifier: identifier) else {
            // Core Location reports the region-count cap, and some setup failures,
            // with no region attached. There is no alert to act on.
            Logger.error("Proximity monitoring failed (\(kind)) without naming a region: \(error)")
            return
        }

        // The region is dead and won't recover on its own, so give its slot back.
        // The alert itself stays stored: it is the rider's, not ours to delete on
        // an OS error, and the next reconciliation gets to try once more.
        Logger.error("Proximity monitoring failed permanently (\(kind)) for alert \(alertID); disarming its region: \(error)")
        service.stopMonitoringProximityAlert(id: alertID)
    }

    // MARK: - Notification Delivery

    private func deliverArrivalNotification(for alert: ProximityAlert) {
        let content = UNMutableNotificationContent()
        content.title = OBALoc(
            "proximity_alert.notification.title",
            value: "Approaching your stop",
            comment: "Title of the notification shown when the rider nears the stop they set a destination alert on."
        )
        content.body = String(
            format: OBALoc(
                "proximity_alert.notification.body_fmt",
                value: "You're getting close to %@.",
                comment: "Body of the destination alert notification. %@ is the name of the rider's destination stop."
            ),
            alert.stopName
        )
        content.sound = .default
        // The stop travels alone when the alert has no region, keeping the shape
        // `PushService` reads for an alert set before the region was recorded.
        var userInfo: [String: Any] = [Self.notificationUserInfoKey: alert.stopID]
        if let regionID = alert.regionID {
            userInfo[Self.notificationRegionUserInfoKey] = regionID
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifierPrefix + alert.id.uuidString,
            content: content,
            trigger: nil // Deliver now.
        )

        // Interpolated up front: the completion handler runs on a notification
        // center queue rather than the main actor, and `alert` is not Sendable.
        let alertID = alert.id.uuidString
        scheduleNotification(request) { error in
            if let error {
                Logger.error("Failed to deliver the notification for proximity alert \(alertID): \(error)")
            }
        }
    }

    /// Whether a notification posted under `status` would reach the rider at all.
    ///
    /// `.provisional` is included even though it delivers quietly, straight to
    /// Notification Center with no banner or sound — a poor fit for an alert whose
    /// whole job is to interrupt someone watching the road. Refusing to set the
    /// alert would still be worse: quiet delivery is delivery, and the rider can
    /// promote it from the notification itself.
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
