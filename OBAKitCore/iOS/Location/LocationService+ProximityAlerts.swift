//
//  LocationService+ProximityAlerts.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation
import CoreLocation

// iOS-only: watchOS has no region monitoring. `LocationService` holds no
// proximity *stored* state directly on the portable class; dynamic state
// is maintained via associated objects.
extension LocationService {

    // MARK: - Retry State

    private final class ProximityRetryState {
        struct Entry {
            var attemptCount: Int
            var task: Task<Void, Never>?
            var region: CLCircularRegion?
        }

        var entries: [String: Entry] = [:]
        var policy: RegionMonitoringRetryPolicy = .standard
        var customSleeper: (@Sendable (TimeInterval) async throws -> Void)?
    }

    private static var retryStateKey: UInt8 = 0

    private var retryState: ProximityRetryState {
        if let state = objc_getAssociatedObject(self, &Self.retryStateKey) as? ProximityRetryState {
            return state
        }
        let state = ProximityRetryState()
        objc_setAssociatedObject(self, &Self.retryStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    /// The retry policy applied when Core Location reports transient region-monitoring failures.
    public var regionMonitoringRetryPolicy: RegionMonitoringRetryPolicy {
        get { retryState.policy }
        set { retryState.policy = newValue }
    }

    /// Injectable sleeper for testing backoff delays without waiting in real time.
    var regionMonitoringSleeper: (@Sendable (TimeInterval) async throws -> Void)? {
        get { retryState.customSleeper }
        set { retryState.customSleeper = newValue }
    }

    func hasPendingRetry(for alert: ProximityAlert) -> Bool {
        hasPendingRetry(forRegionIdentifier: Self.proximityRegionIdentifier(for: alert))
    }

    func hasPendingRetry(forRegionIdentifier identifier: String) -> Bool {
        retryState.entries[identifier]?.task != nil
    }

    func pendingRetryTask(for alert: ProximityAlert) -> Task<Void, Never>? {
        pendingRetryTask(forRegionIdentifier: Self.proximityRegionIdentifier(for: alert))
    }

    func pendingRetryTask(forRegionIdentifier identifier: String) -> Task<Void, Never>? {
        retryState.entries[identifier]?.task
    }

    func retryAttemptCount(for alert: ProximityAlert) -> Int {
        retryAttemptCount(forRegionIdentifier: Self.proximityRegionIdentifier(for: alert))
    }

    func retryAttemptCount(forRegionIdentifier identifier: String) -> Int {
        retryState.entries[identifier]?.attemptCount ?? 0
    }

    func cancelRetry(for identifier: String) {
        if let entry = retryState.entries.removeValue(forKey: identifier) {
            entry.task?.cancel()
        }
    }

    func cancelAllRetries() {
        for (_, entry) in retryState.entries {
            entry.task?.cancel()
        }
        retryState.entries.removeAll()
    }

    // MARK: - Region Monitoring

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

    private func notifyDelegatesDidEnterMonitoredRegion(_ identifier: String) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, didEnterMonitoredRegion: identifier)
        }
    }

    private func notifyDelegatesMonitoringDidFail(_ identifier: String?, error: Error, kind: RegionMonitoringFailureKind) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, monitoringDidFailFor: identifier, error: error, kind: kind)
        }
    }

    static let proximityRegionPrefix = "oba.proximity."

    /// The number of regions iOS will monitor for a single app, across every
    /// feature that asks for one.
    ///
    /// Core Location does not expose this as a constant, and it enforces the cap
    /// asynchronously: the call that exceeds it returns normally, then fails via
    /// `monitoringDidFailFor` carrying no region at all. Checking up front is the
    /// only way to tell the caller *which* alert failed to arm.
    public static let maximumMonitoredRegions = 20

    static func proximityRegionIdentifier(for alert: ProximityAlert) -> String {
        proximityRegionIdentifier(forAlertID: alert.id)
    }

    /// Builds the same identifier from an alert's ID alone.
    ///
    /// An alert deleted while the app wasn't running leaves its region armed with
    /// no `ProximityAlert` left to name it, so the ID has to be enough.
    static func proximityRegionIdentifier(forAlertID id: UUID) -> String {
        proximityRegionPrefix + id.uuidString
    }

    /// Recovers the proximity alert a monitored region belongs to, or nil for a
    /// region this service did not create.
    ///
    /// `didEnterMonitoredRegion` and `monitoringDidFailFor` hand their delegates a
    /// bare identifier string, and the prefix-plus-UUID encoding behind it is
    /// built a few lines above. Decoding it here as well keeps consumers from
    /// reconstructing a format they don't own — the two drifting apart would
    /// strand every alert with nothing to attribute a geofence event to.
    public static func proximityAlertID(forRegionIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(proximityRegionPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(proximityRegionPrefix.count)))
    }

    /// The regions currently monitored on behalf of proximity alerts, excluding
    /// any the app monitors for other reasons.
    public var monitoredProximityRegions: Set<CLRegion> {
        regionMonitor.monitoredRegions.filter { $0.identifier.hasPrefix(Self.proximityRegionPrefix) }
    }

    /// The IDs of the proximity alerts currently armed.
    ///
    /// Monitored regions outlive the process that armed them, while the alerts
    /// explaining those regions live in `UserDataStore` and expire on a clock.
    /// Comparing the two sets is what tells a consumer which alerts still need
    /// arming and which regions were left behind by alerts that are gone.
    public var monitoredProximityAlertIDs: Set<UUID> {
        Set(monitoredProximityRegions.compactMap { Self.proximityAlertID(forRegionIdentifier: $0.identifier) })
    }

    /// Starts monitoring a geofence region for the given proximity alert.
    ///
    /// The result is deliberately *not* `@discardableResult`. Region monitoring
    /// has no self-healing re-arm — nothing retries it when authorization or the
    /// region count later changes — so a caller that drops a failure on the floor
    /// ships an alert that will never fire and never explains why.
    public func startMonitoringProximity(for alert: ProximityAlert) -> ProximityMonitoringResult {
        guard isProximityMonitoringAuthorized else {
            Logger.warn("Not monitoring proximity alert \(alert.id): needs authorizedAlways, have \(authorizationStatus).")
            return .insufficientAuthorization(authorizationStatus)
        }

        let identifier = Self.proximityRegionIdentifier(for: alert)
        cancelRetry(for: identifier)

        // Re-arming an alert already being monitored replaces its region instead
        // of adding one — `CLRegion` hashes on identifier — so it can't push the
        // app over the cap and must not be rejected by this check.
        let isReplacement = regionMonitor.monitoredRegions.contains { $0.identifier == identifier }
        if !isReplacement, regionMonitor.monitoredRegions.count >= Self.maximumMonitoredRegions {
            Logger.warn("Not monitoring proximity alert \(alert.id): already at the \(Self.maximumMonitoredRegions)-region limit.")
            return .regionLimitReached(limit: Self.maximumMonitoredRegions)
        }

        // Clamp deliberately and report it. Core Location answers an oversize
        // radius with `CLError.regionMonitoringFailure`, which arrives
        // asynchronously through `monitoringDidFailFor` carrying no radius — too
        // late, and too vague, to tell the rider their alert would have fired
        // somewhere other than where they asked.
        //
        // `-1` is not an unknown limit. Apple documents it as region monitoring
        // being unavailable or unsupported on this device, so honouring the
        // request in that case hands the caller `.started` for an alert that can
        // never fire. Left that way for now — the failure does still surface
        // through `monitoringDidFailFor` — but refusing up front wants an
        // `isMonitoringAvailable(for:)` check and a result case to carry it.
        // Both points flagged in review of #1292.
        let requestedRadius = alert.radiusMeters
        let deviceMaximum = regionMonitor.maximumRegionMonitoringDistance
        let radius = deviceMaximum > 0 ? min(requestedRadius, deviceMaximum) : requestedRadius

        let region = CLCircularRegion(center: alert.coordinate, radius: radius, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false

        retryState.entries[identifier] = ProximityRetryState.Entry(attemptCount: 0, task: nil, region: region)

        regionMonitor.startMonitoring(for: region)

        guard radius == requestedRadius else {
            Logger.warn("Proximity alert \(alert.id) radius \(requestedRadius)m exceeds the device maximum \(deviceMaximum)m; monitoring at \(radius)m.")
            return .startedWithClampedRadius(requested: requestedRadius, monitored: radius)
        }

        return .started
    }

    /// Stops monitoring the geofence region for the given proximity alert.
    public func stopMonitoringProximity(for alert: ProximityAlert) {
        stopMonitoringProximityAlert(id: alert.id)
    }

    /// Stops monitoring the geofence region armed for `id`, whether or not an
    /// alert with that ID still exists.
    ///
    /// The counterpart to `stopMonitoringProximity(for:)` for the case that has no
    /// alert to pass: a region whose alert was deleted or expired in an earlier
    /// run of the app still holds one of the twenty slots, and only its ID
    /// survives to identify it.
    public func stopMonitoringProximityAlert(id: UUID) {
        let identifier = Self.proximityRegionIdentifier(forAlertID: id)
        cancelRetry(for: identifier)
        guard let matchingRegion = regionMonitor.monitoredRegions.first(where: {
            $0.identifier == identifier
        }) else {
            Logger.warn("No monitored region found for proximity alert \(id)")
            return
        }
        regionMonitor.stopMonitoring(for: matchingRegion)
    }

    /// Stops monitoring all proximity alert regions without affecting other monitored regions.
    public func stopMonitoringAllProximityAlerts() {
        cancelAllRetries()
        for region in monitoredProximityRegions {
            regionMonitor.stopMonitoring(for: region)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard region.identifier.hasPrefix(Self.proximityRegionPrefix) else { return }
        retryState.entries[region.identifier]?.attemptCount = 0
        retryState.entries[region.identifier]?.task = nil
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix(Self.proximityRegionPrefix) else { return }

        // Every region registered under this prefix is created as a
        // `CLCircularRegion` a few lines above, so one that isn't means either a
        // bug here or something else writing into our identifier namespace.
        // Returning silently would strand the alert with nothing to debug from.
        guard region is CLCircularRegion else {
            Logger.error("Entered region \(region.identifier) carrying the proximity prefix but typed \(type(of: region)) rather than CLCircularRegion. Ignoring.")
            return
        }

        retryState.entries[region.identifier]?.attemptCount = 0
        cancelRetry(for: region.identifier)
        notifyDelegatesDidEnterMonitoredRegion(region.identifier)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let kind = RegionMonitoringFailureKind(error: error)

        guard let identifier = region?.identifier else {
            // Core Location reports the region-count cap, and some setup
            // failures, with no region attached. Unattributable, but plausibly
            // one of ours, so it still goes to the delegates.
            Logger.error("Region monitoring failed with no region attached (\(kind)): \(error)")
            notifyDelegatesMonitoringDidFail(nil, error: error, kind: kind)
            return
        }

        // Mirrors the prefix filter in `didEnterRegion`. Without it, proximity
        // delegates receive every monitoring failure in the app — including ones
        // they can neither attribute nor act on.
        guard identifier.hasPrefix(Self.proximityRegionPrefix) else {
            Logger.error("Region monitoring failed for non-proximity region \(identifier) (\(kind)): \(error)")
            return
        }

        guard kind.isTransient else {
            Logger.error("Region monitoring failed permanently for proximity region \(identifier) (\(kind)): \(error)")
            cancelRetry(for: identifier)
            notifyDelegatesMonitoringDidFail(identifier, error: error, kind: kind)
            return
        }

        // Only retry transient failures if an entry already exists for an alert that is currently tracked and wanted.
        guard let entry = retryState.entries[identifier] else {
            Logger.warn("Region monitoring transient failure ignored for untracked or deleted proximity region \(identifier) (\(kind)): \(error)")
            return
        }

        let previousAttempt = entry.attemptCount
        let currentAttempt = previousAttempt + 1

        guard currentAttempt <= regionMonitoringRetryPolicy.maxAttempts else {
            Logger.error("Region monitoring transient retries exhausted (\(regionMonitoringRetryPolicy.maxAttempts) attempts) for proximity region \(identifier) (\(kind)): \(error)")
            cancelRetry(for: identifier)
            notifyDelegatesMonitoringDidFail(identifier, error: error, kind: kind)
            return
        }

        let delay = regionMonitoringRetryPolicy.delay(forAttempt: currentAttempt)
        Logger.info("Region monitoring delayed/transient error for proximity region \(identifier) (\(kind)): scheduling retry attempt \(currentAttempt)/\(regionMonitoringRetryPolicy.maxAttempts) in \(delay)s.")

        let targetRegion: CLCircularRegion? = (region as? CLCircularRegion) ?? entry.region

        entry.task?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            if delay > 0 {
                do {
                    if let customSleeper = self.regionMonitoringSleeper {
                        try await customSleeper(delay)
                    } else {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            guard self.isProximityMonitoringAuthorized else {
                Logger.warn("Retry aborted for proximity region \(identifier): authorization is no longer Always (\(self.authorizationStatus)).")
                self.cancelRetry(for: identifier)
                return
            }

            let isReplacement = self.regionMonitor.monitoredRegions.contains { $0.identifier == identifier }
            if !isReplacement, self.regionMonitor.monitoredRegions.count >= Self.maximumMonitoredRegions {
                Logger.warn("Retry aborted for proximity region \(identifier): region limit reached.")
                self.cancelRetry(for: identifier)
                return
            }

            guard let circularRegion = targetRegion else {
                Logger.error("Retry aborted for proximity region \(identifier): no circular region available to monitor.")
                self.cancelRetry(for: identifier)
                self.notifyDelegatesMonitoringDidFail(identifier, error: error, kind: kind)
                return
            }

            Logger.info("Retrying region monitoring (attempt \(currentAttempt)) for proximity region \(identifier).")
            self.regionMonitor.stopMonitoring(for: circularRegion)
            self.regionMonitor.startMonitoring(for: circularRegion)
            if self.retryState.entries[identifier]?.attemptCount == currentAttempt {
                self.retryState.entries[identifier]?.task = nil
            }
        }

        retryState.entries[identifier] = ProximityRetryState.Entry(
            attemptCount: currentAttempt,
            task: task,
            region: targetRegion
        )
    }
}

#endif // os(iOS)
