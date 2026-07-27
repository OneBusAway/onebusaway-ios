//
//  LocationService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

@objc(OBALocationServiceDelegate)
@MainActor
public protocol LocationServiceDelegate: NSObjectProtocol {
    @objc optional func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus)
    /// Fired when the accuracy authorization changes *without* the coarse
    /// `CLAuthorizationStatus` changing — e.g. the user grants one-shot full
    /// accuracy ("Allow Once") or toggles Precise Location in Settings. These
    /// transitions leave `authorizationStatusChanged` silent, so consumers that
    /// react to accuracy (map status pills, zoom level) must observe this too.
    @objc optional func locationService(_ service: LocationService, accuracyAuthorizationChanged accuracyAuthorization: CLAccuracyAuthorization)
    @objc optional func locationService(_ service: LocationService, locationChanged location: CLLocation)
    @objc optional func locationService(_ service: LocationService, headingChanged heading: CLHeading?)
    @objc optional func locationService(_ service: LocationService, errorReceived error: Error)
    @objc optional func locationService(_ service: LocationService, didEnterMonitoredRegion identifier: String)
    @objc optional func locationService(_ service: LocationService, monitoringDidFailFor identifier: String?, error: Error)
}

// @preconcurrency: CLLocationManager delivers callbacks on the run loop it was
// created on, which for this service is always the main run loop.
// Callers of the designated initializer must construct the injected manager
// on the main thread for the same reason.
@objc(OBALocationService) @MainActor public class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private var locationManager: LocationManager

    public convenience override init() {
        self.init(userDefaults: UserDefaults.standard, locationManager: CLLocationManager())
    }

    public init(userDefaults: UserDefaults, locationManager: LocationManager) {
        self.locationManager = locationManager
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

    // MARK: - User Defaults

    private let userDefaults: UserDefaults

    private struct UserDefaultsKeys {
        static let promptUserForLocationPermission = "LocationService.promptUserForLocationPermission"
        static let locationServicesDenied = "LocationService.locationServicesDenied"
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [UserDefaultsKeys.promptUserForLocationPermission: true])
    }

    // MARK: - Location Properties

    public private(set) var currentLocation: CLLocation? {
        didSet {
            if let currentLocation = currentLocation {
                notifyDelegatesLocationChanged(currentLocation)
            }
        }
    }

    public private(set) var currentHeading: CLHeading? {
        didSet {
            notifyDelegatesHeadingChanged(currentHeading)
        }
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<LocationServiceDelegate>.weakObjects()

    public func addDelegate(_ delegate: LocationServiceDelegate) {
        delegates.add(delegate)
    }

    public func removeDelegate(_ delegate: LocationServiceDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesAuthorizationChanged(_ status: CLAuthorizationStatus) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, authorizationStatusChanged: status)
        }
    }

    private func notifyDelegatesAccuracyAuthorizationChanged(_ accuracyAuthorization: CLAccuracyAuthorization) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, accuracyAuthorizationChanged: accuracyAuthorization)
        }
    }

    private func notifyDelegatesLocationChanged(_ location: CLLocation) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, locationChanged: location)
        }
    }

    private func notifyDelegatesHeadingChanged(_ heading: CLHeading?) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, headingChanged: heading)
        }
    }

    private func notifyDelegatesErrorReceived(_ error: Error) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, errorReceived: error)
        }
    }

    private func notifyDelegatesDidEnterMonitoredRegion(_ identifier: String) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, didEnterMonitoredRegion: identifier)
        }
    }

    private func notifyDelegatesMonitoringDidFail(_ identifier: String?, error: Error) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, monitoringDidFailFor: identifier, error: error)
        }
    }

    // MARK: - Authorization

    /// The app's own authorization, exactly as Core Location reports it.
    private var rawAuthorizationStatus: CLAuthorizationStatus

    /// Latched when Core Location reports a `denied` error. This happens even
    /// while `rawAuthorizationStatus` still reads as authorized — most commonly
    /// when the user switches Location Services off system-wide, which does not
    /// change the app's per-app authorization.
    ///
    /// Persisted, because that system-wide state outlives the app process while
    /// the per-app authorization that masks it does not. See the seeding comment
    /// in `init(userDefaults:locationManager:)`.
    private var locationServicesDenied: Bool {
        didSet {
            guard locationServicesDenied != oldValue else { return }
            userDefaults.set(locationServicesDenied, forKey: UserDefaultsKeys.locationServicesDenied)
        }
    }

    private var isPerAppAuthorized: Bool {
        rawAuthorizationStatus == .authorizedWhenInUse || rawAuthorizationStatus == .authorizedAlways
    }

    /// The current *effective* authorization state of the app.
    ///
    /// When the `locationServicesDenied` latch is set, this reports `.denied`
    /// even though the per-app authorization still reads as authorized. That is
    /// deliberate: consumers switch on this value to decide what to show
    /// (`MapViewModel.topPillState`, `MapStatusView.state(for:)`), and a user
    /// whose location is unusable needs the "Location Services Off / Turn On in
    /// Settings" pill, not a silent absence of the locate button. The latch is
    /// ignored while the app is not itself authorized, so `.notDetermined`
    /// survives and the app can still prompt.
    public var authorizationStatus: CLAuthorizationStatus {
        guard locationServicesDenied, isPerAppAuthorized else { return rawAuthorizationStatus }
        return .denied
    }

    /// The single funnel for both inputs to `authorizationStatus`. It applies
    /// the new values and *then* reacts once to the effective transition.
    ///
    /// Property observers on the two inputs can't do this correctly: whichever
    /// one is assigned first sees the other's stale value, and both firing
    /// means delegates get notified twice for one logical change.
    private func applyAuthorizationState(rawStatus: CLAuthorizationStatus, servicesDenied: Bool) {
        let oldStatus = authorizationStatus
        let wasAuthorized = isLocationUseAuthorized

        rawAuthorizationStatus = rawStatus
        locationServicesDenied = servicesDenied

        guard authorizationStatus != oldStatus else { return }

        notifyDelegatesAuthorizationChanged(authorizationStatus)

        if isLocationUseAuthorized {
            startUpdates()
        } else if wasAuthorized {
            // Access was revoked. Tear the manager down here — nobody else will,
            // and a `CLLocationManager` left running keeps the location-usage
            // indicator lit and the magnetometer powered for the rest of the
            // process.
            stopUpdates()
        }
    }

    /// This is true when the app is in a state such that the user can/should be
    /// prompted for location services authorization. In other words: the app has
    /// not been denied or approved, and the user also has not generally restricted
    /// access to location services.
    public var canRequestAuthorization: Bool {
        return authorizationStatus == .notDetermined
    }

    /// True if the app is allowed to prompt the user for permission and false otherwise.
    ///
    /// We have this extra check in place in order to make sure that we only use our
    /// one chance to request location permissions in a case where the user will
    /// actually agree to it.
    public var canPromptUserForPermission: Bool {
        get {
            userDefaults.bool(forKey: UserDefaultsKeys.promptUserForLocationPermission)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultsKeys.promptUserForLocationPermission)
        }
    }

    /// Prompts the user for permission to access location services. (e.g. GPS.)
    @objc public func requestInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    @available(iOS 14, *)
    @objc public func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    /// Answers the question of whether the device GPS can be consulted for location data.
    ///
    /// Derived from the effective `authorizationStatus`. We deliberately avoid
    /// `CLLocationManager.locationServicesEnabled()` because it performs a
    /// blocking, synchronous XPC call that Apple warns can hang the main thread.
    /// When location services are disabled system-wide, attempts to start
    /// updates fail via `locationManager(_:didFailWithError:)` with a `denied`
    /// error, which we latch — the pattern Apple recommends.
    public var isLocationUseAuthorized: Bool {
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    @available(iOS 14, *)
    public var accuracyAuthorization: CLAccuracyAuthorization {
        return locationManager.accuracyAuthorization
    }

    /// Last accuracy authorization we notified delegates about. Tracked so a
    /// `locationManagerDidChangeAuthorization` callback that carries only an
    /// accuracy change (coarse status unchanged) can still be detected and
    /// forwarded via `accuracyAuthorizationChanged`.
    private var lastAccuracyAuthorization: CLAccuracyAuthorization

    // MARK: - State Management

    public func startUpdates() {
        startUpdatingLocation()
        startUpdatingHeading()
    }

    public func stopUpdates() {
        stopUpdatingLocation()
        stopUpdatingHeading()
    }

    // MARK: - Location

    public func startUpdatingLocation() {
        guard isLocationUseAuthorized else {
            return
        }

        locationManager.startUpdatingLocation()
    }

    /// Unlike its `start` counterpart this is unguarded: stopping is always safe,
    /// and gating it on authorization would make a manager we started before
    /// access was revoked impossible to ever turn off.
    public func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Heading

    public func startUpdatingHeading() {
        guard locationManager.isHeadingAvailable else {
            return
        }

        locationManager.startUpdatingHeading()
    }

    public func stopUpdatingHeading() {
        guard locationManager.isHeadingAvailable else {
            return
        }

        locationManager.stopUpdatingHeading()
    }

    // MARK: - Delegate

    /// Attempts to resume location updates after a latched `denied` error.
    ///
    /// Toggling Location Services back on system-wide does not change the app's
    /// per-app authorization, so Core Location may deliver no authorization
    /// callback at all — nothing would otherwise clear the latch, and the locate
    /// button and user dot would stay hidden until the app was force-quit. The
    /// app calls this when it returns to the foreground, which is where the user
    /// lands after visiting Settings.
    ///
    /// This probes rather than assumes: the latch stays set until we have an
    /// answer, so the UI does not flash location affordances on and back off.
    /// A fix clears the latch (see `locationManager(_:didUpdateLocations:)`);
    /// another `denied` error leaves it exactly as it was.
    public func retryIfLocationServicesDenied() {
        guard locationServicesDenied, isPerAppAuthorized else { return }
        locationManager.startUpdatingLocation()
    }

    @available(iOS 14, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // A *change* of per-app authorization means the user just made a fresh
        // decision, so any latched `denied` state is stale evidence and we
        // re-arm optimistically. A callback that leaves the status untouched
        // carries no new information — Core Location fires one whenever a
        // delegate is assigned — so it must not clear the latch, or every
        // spurious callback would restart updates against a location subsystem
        // that is still off.
        //
        // Read the status from the injected manager, not from `manager`, so the
        // path under test is the path that ships.
        let newStatus = locationManager.authorizationStatus
        let statusChanged = newStatus != rawAuthorizationStatus
        applyAuthorizationState(rawStatus: newStatus, servicesDenied: statusChanged ? false : locationServicesDenied)

        // Core Location delivers a callback as soon as the delegate is assigned,
        // carrying an *unchanged* status. That is the app's earliest signal that
        // it is authorized, and it is where location updates have always been
        // started from — early enough that the first fix lands before the map
        // settles. `applyAuthorizationState` deliberately reacts only to
        // transitions, so starting updates has to happen outside of it or a
        // relaunch of an already-authorized app would wait for the next
        // foreground. Both calls below are idempotent.
        if isLocationUseAuthorized {
            startUpdates()
        } else {
            // Same reasoning for a latch seeded from the previous launch: probe
            // it now rather than making the user wait for a foreground event.
            retryIfLocationServicesDenied()
        }

        // Accuracy can change while the coarse status stays put (e.g. "Allow
        // Once" elevates a reduced-accuracy session to full). That leaves the
        // `authorizationStatus` didSet silent, so detect and forward the
        // accuracy transition on its own channel.
        let newAccuracy = manager.accuracyAuthorization
        if newAccuracy != lastAccuracyAuthorization {
            lastAccuracyAuthorization = newAccuracy
            notifyDelegatesAccuracyAuthorizationChanged(newAccuracy)
        }
    }

    public var successiveLocationComparisonWindow: TimeInterval = 60.0

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }

        // A fix is proof that location is usable again, whatever we last latched.
        if locationServicesDenied {
            applyAuthorizationState(rawStatus: rawAuthorizationStatus, servicesDenied: false)
        }

        guard let currentLocation = currentLocation else {
            self.currentLocation = newLocation
            return
        }

        // We have this issue where we get a high-accuracy location reading immediately
        // followed by a low-accuracy location reading, such as if wifi-localization
        // completed before cell-tower-localization.  We want to ignore the low-accuracy
        // reading.
        let interval = newLocation.timestamp.timeIntervalSince(currentLocation.timestamp)
        if interval < successiveLocationComparisonWindow && currentLocation.horizontalAccuracy < newLocation.horizontalAccuracy {
            Logger.info("Pruning location reading with low accuracy.")
            return
        }

        self.currentLocation = newLocation
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A `denied` error means location is currently unavailable even if the
        // per-app authorization still reads as authorized (e.g. Location
        // Services switched off system-wide). Latching it flips the effective
        // `authorizationStatus` to `.denied`, which stops updates as Apple
        // recommends and lets the UI explain the situation.
        if let clError = error as? CLError, clError.code == .denied {
            // Unconditional, as Apple recommends: a probe that re-confirms an
            // already-latched denial must still leave the manager stopped, and
            // `applyAuthorizationState` only reacts to state *transitions*.
            stopUpdates()
            applyAuthorizationState(rawStatus: rawAuthorizationStatus, servicesDenied: true)
        }

        notifyDelegatesErrorReceived(error)
    }

    // MARK: - Region Monitoring

    static let proximityRegionPrefix = "oba.proximity."

    /// Starts monitoring a geofence region for the given proximity alert.
    ///
    /// - Note: Region monitoring requires `.authorizedAlways` for background delivery.
    ///   The caller (e.g. ProximityAlertManager) is responsible for ensuring appropriate authorization.
    public func startMonitoringProximity(for alert: ProximityAlert) {
        guard isLocationUseAuthorized else { return }

        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: Self.proximityRegionPrefix + alert.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        locationManager.startMonitoring(for: region)
    }

    /// Stops monitoring the geofence region for the given proximity alert.
    public func stopMonitoringProximity(for alert: ProximityAlert) {
        let identifier = Self.proximityRegionPrefix + alert.id.uuidString
        guard let matchingRegion = locationManager.monitoredRegions.first(where: {
            $0.identifier == identifier
        }) else {
            Logger.warn("No monitored region found for proximity alert \(alert.id)")
            return
        }
        locationManager.stopMonitoring(for: matchingRegion)
    }

    /// Stops monitoring all proximity alert regions without affecting other monitored regions.
    public func stopMonitoringAllProximityAlerts() {
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix(Self.proximityRegionPrefix) {
            locationManager.stopMonitoring(for: region)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region is CLCircularRegion, region.identifier.hasPrefix(Self.proximityRegionPrefix) else { return }
        notifyDelegatesDidEnterMonitoredRegion(region.identifier)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger.error("Region monitoring failed for \(region?.identifier ?? "unknown"): \(error)")
        notifyDelegatesMonitoringDidFail(region?.identifier, error: error)
    }
}
