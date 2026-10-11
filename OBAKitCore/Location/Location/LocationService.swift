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

/// Errors thrown by `LocationService.requestLocation(desiredAccuracy:)`.
public enum LocationServiceError: LocalizedError {
    /// The app is not authorized to use location, so no request was made.
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return OBALoc("location_service.error.not_authorized", value: "Location access is not authorized.", comment: "Error shown when a location request is made without authorization")
        }
    }
}

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
    /// Fired when Core Location fails to monitor one of *our* proximity regions.
    ///
    /// Failures for regions the app monitors for other reasons are filtered out
    /// before this point, mirroring the prefix check in `didEnterMonitoredRegion`.
    /// `identifier` is nil when Core Location could not attribute the failure to a
    /// region; those are forwarded anyway, since one of ours may be the cause.
    ///
    /// `kind` classifies `error` into what the receiver can actually do about it —
    /// see `RegionMonitoringFailureKind`.
    @objc optional func locationService(_ service: LocationService, monitoringDidFailFor identifier: String?, error: Error, kind: RegionMonitoringFailureKind)
}

// @preconcurrency: CLLocationManager delivers callbacks on the run loop it was
// created on, which for this service is always the main run loop.
// Callers of the designated initializer must construct the injected manager
// on the main thread for the same reason.
@objc(OBALocationService) @MainActor public class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    // Internal, not private: `LocationService+ProximityAlerts.swift` is a
    // cross-file extension and needs to reach it.
    var locationManager: LocationManager

    private let startsUpdatesOnAuthorization: Bool

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

    // MARK: - User Defaults

    private let userDefaults: UserDefaults

    private struct UserDefaultsKeys {
        static let promptUserForLocationPermission = "LocationService.promptUserForLocationPermission"
        static let promptUserForAlwaysAuthorization = "LocationService.promptUserForAlwaysAuthorization"
        static let locationServicesDenied = "LocationService.locationServicesDenied"
    }

    private func registerDefaults() {
        userDefaults.register(defaults: [
            UserDefaultsKeys.promptUserForLocationPermission: true,
            UserDefaultsKeys.promptUserForAlwaysAuthorization: true
        ])
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

    let delegates = NSHashTable<LocationServiceDelegate>.weakObjects()

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
        rawAuthorizationStatus.isAuthorized
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

    /// The single funnel for both inputs to `authorizationStatus`. It applies the
    /// new values, reconciles the manager's running state to match, and notifies
    /// delegates once on an effective transition.
    ///
    /// Property observers on the two inputs can't do this correctly: whichever
    /// one is assigned first sees the other's stale value, and both firing means
    /// delegates get notified twice for one logical change.
    ///
    /// Reconciliation is unconditional (not gated on the transition) and relies on
    /// `startUpdates()`/`stopUpdates()` being idempotent. That is deliberate: Core
    /// Location fires an authorization callback carrying an *unchanged* status the
    /// moment the delegate is assigned, and an already-authorized app must start
    /// its first fix from it. Reconciling here means there is a single place that
    /// starts updates — no separate post-funnel start path that would fire a
    /// second time on a real grant (and, with services off, produce two failed
    /// probes and two error callbacks).
    private func applyAuthorizationState(rawStatus: CLAuthorizationStatus, servicesDenied: Bool) {
        let oldStatus = authorizationStatus

        rawAuthorizationStatus = rawStatus
        locationServicesDenied = servicesDenied

        // Reconcile running state to the effective authorization. When access is
        // revoked this is what tears the manager down — nobody else will, and a
        // `CLLocationManager` left running keeps the location-usage indicator lit
        // and the magnetometer powered for the rest of the process.
        if isLocationUseAuthorized {
            if startsUpdatesOnAuthorization {
                startUpdates()
            }
        } else {
            stopUpdates()
        }

        guard authorizationStatus != oldStatus else { return }
        notifyDelegatesAuthorizationChanged(authorizationStatus)
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

    /// Whether the one-time Always upgrade prompt is still available to spend.
    ///
    /// iOS surfaces that prompt once per install and silently does nothing on
    /// every later call, so an app with no record of having spent it cannot tell
    /// "asking will show a prompt" from "asking will do nothing" — and therefore
    /// cannot know when to stop asking and send the rider to Settings instead.
    ///
    /// Read-only, and persisted rather than held in memory: the limit is per
    /// install, not per launch. ``requestAlwaysAuthorization()`` is the only
    /// thing that clears it, deliberately — the sibling
    /// ``canPromptUserForPermission`` leaves that to its callers, and one of the
    /// two call sites in this app already forgets to.
    ///
    /// - Note: This records what the app *asked*, which is not always what iOS
    ///   *showed*. A rider who answered the first prompt with "Allow Once" leaves
    ///   the status at `.authorizedWhenInUse` while Apple documents further
    ///   upgrade requests as ignored, and `CLAuthorizationStatus` offers no way to
    ///   tell that apart from an ordinary When In Use grant, so the flag is spent
    ///   on a prompt nobody saw. That degrades to the Settings route rather than
    ///   breaking anything, which is why it is documented rather than detected.
    public var canPromptForAlwaysAuthorization: Bool {
        userDefaults.bool(forKey: UserDefaultsKeys.promptUserForAlwaysAuthorization)
    }

    /// Prompts the user to upgrade to Always authorization, which region
    /// monitoring requires to deliver geofence events in the background.
    ///
    /// Apple only surfaces this prompt once, and only from `.authorizedWhenInUse`
    /// or `.notDetermined` — calling it from `.denied` or `.restricted` does
    /// nothing at all. Callers should therefore treat it as a one-shot upgrade
    /// path and fall back to deep-linking Settings when it no-ops.
    ///
    /// Refuses, and logs, from any *status* Core Location would reject the
    /// request from, so nothing is spent where nothing could have been raised. It
    /// also refuses once ``canPromptForAlwaysAuthorization`` is gone, which is
    /// what stops a caller asking forever into silence.
    ///
    /// - Important: This also requires `NSLocationAlwaysAndWhenInUseUsageDescription`
    ///   in the host app's Info.plist; without it iOS ignores the call entirely.
    ///   `Apps/Shared/app_shared.yml` declares it for every white-label app, and
    ///   KiedyBus overrides the body with its own. A new app that skips both will
    ///   never reach `.authorizedAlways`, and this method will silently do nothing
    ///   — while still spending ``canPromptForAlwaysAuthorization``, because the
    ///   status looks promptable and nothing reports back that no prompt appeared.
    ///   The status guard above cannot cover this; only the Info.plist can.
    @objc public func requestAlwaysAuthorization() {
        guard authorizationStatus == .notDetermined || authorizationStatus == .authorizedWhenInUse else {
            Logger.warn("Not requesting Always authorization from \(authorizationStatus): iOS only raises that prompt from notDetermined or authorizedWhenInUse.")
            return
        }

        guard canPromptForAlwaysAuthorization else {
            Logger.warn("Not requesting Always authorization: this install already spent its one-time prompt. Settings is the only route left.")
            return
        }

        userDefaults.set(false, forKey: UserDefaultsKeys.promptUserForAlwaysAuthorization)
        locationManager.requestAlwaysAuthorization()
    }

    /// Whether the app can actually run proximity geofences.
    ///
    /// Deliberately stricter than `isLocationUseAuthorized`, which also accepts
    /// `.authorizedWhenInUse`. Region monitoring started under When In Use is
    /// accepted by Core Location but only delivers while the app is in use — which
    /// defeats the entire purpose of a proximity alert, since the user is watching
    /// the road, not the screen.
    public var isProximityMonitoringAuthorized: Bool {
        authorizationStatus == .authorizedAlways
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
        return authorizationStatus.isAuthorized
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
    ///
    /// Also fails any pending one-shot waiters. Stopping cancels a pending
    /// `requestLocation()` and Core Location sends no callback afterwards, so
    /// without this they would stay suspended forever, and so would every later
    /// caller that queued up behind them. Revocation, the services-off latch
    /// and external stops all come through here.
    public func stopUpdatingLocation() {
        failOneShotRequests(with: LocationServiceError.notAuthorized)
        locationManager.stopUpdatingLocation()
    }

    // MARK: - One-shot location

    /// Callers suspended in `requestLocation(desiredAccuracy:)`. All resolve on
    /// the next `didUpdateLocations` / `didFailWithError`, whichever comes first.
    /// Internal read access so tests can wait until every caller is suspended.
    private(set) var pendingOneShotRequests: [CheckedContinuation<CLLocation, Error>] = []

    /// Requests a single fix and suspends until the manager delivers one.
    ///
    /// The fix **also becomes `currentLocation`, bypassing the accuracy prune**
    /// that continuous updates apply, so `locationChanged` reaches every
    /// delegate (`RegionsService` selects the region from it). A caller asked
    /// for this fix; a coarser-than-last answer is still the answer. Concurrent
    /// callers share one manager request. A stop while a request is pending
    /// (revocation, Location Services turned off, or `stopUpdatingLocation()`)
    /// fails the waiters with ``LocationServiceError/notAuthorized``.
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

    // MARK: - Heading

    /// Guarded on authorization as well as availability. `isHeadingAvailable`
    /// wraps `CLLocationManager.headingAvailable()`, which reports whether the
    /// *device* has a magnetometer — it says nothing about whether we may use it.
    /// Without the authorization guard, `startUpdates()` would start heading even
    /// when starting location had just synchronously latched a `denied` error and
    /// torn the manager down, leaving the magnetometer powered for the rest of
    /// the process.
    public func startUpdatingHeading() {
        guard isLocationUseAuthorized, locationManager.isHeadingAvailable else {
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

    /// Reconciles the denied latch against the system-wide Location Services
    /// switch, read off the main thread.
    ///
    /// This is the authoritative signal the latch approximates. `didFailWithError`
    /// (a `denied` error) and `didUpdateLocations` (a fix) are the async proxies
    /// we also honor between probes, but each has a blind spot: toggling Location
    /// Services back on delivers no authorization callback and, indoors, no fix
    /// either — so a latch cleared only by those signals could stay stuck for a
    /// whole session. Reading the real switch recovers regardless, and latches a
    /// services-off launch without waiting for the first `denied` error to arrive.
    ///
    /// The read is a blocking XPC call, hence off the main thread; the result is
    /// applied back on the main actor. It reconciles both directions, so a single
    /// call covers "services came back on" and "services are off."
    /// The in-flight probe, if any.
    ///
    /// Probes are single-flight by cancel-and-replace. Three call sites can start
    /// one — the authorization callback, `retryIfLocationServicesDenied()`, and
    /// foregrounding by way of the latter — and unstructured tasks have no
    /// ordering guarantee at the `await`, so an older read could land after a
    /// newer one and clobber the latch with stale state. Cancelling the previous
    /// probe makes the newest read the only one that applies.
    private var servicesProbeTask: Task<Void, Never>?

    private func refreshLocationServicesEnabled() {
        // The latch is only meaningful while the app is itself authorized; when it
        // isn't, `authorizationStatus` reports the raw status directly and there is
        // nothing to reconcile.
        guard isPerAppAuthorized else { return }

        servicesProbeTask?.cancel()
        servicesProbeTask = Task { [weak self] in
            guard let self else { return }
            let enabled = await self.locationManager.locationServicesEnabled()

            // Cancellation cannot interrupt the blocking read itself, so a
            // superseded probe resumes here with an answer it must not apply.
            guard !Task.isCancelled, self.isPerAppAuthorized else { return }

            self.servicesProbeTask = nil
            self.applyAuthorizationState(rawStatus: self.rawAuthorizationStatus, servicesDenied: !enabled)
        }
    }

    /// Attempts to recover from a latched `denied` error, e.g. when the app
    /// returns to the foreground after the user visited Settings.
    ///
    /// Toggling Location Services back on system-wide does not change the app's
    /// per-app authorization, so Core Location may deliver no authorization
    /// callback at all — nothing would otherwise clear the latch, and the locate
    /// button and user dot would stay hidden until the app was force-quit.
    ///
    /// Recovery goes through the off-main `locationServicesEnabled` probe rather
    /// than optimistically restarting updates: the latch stays set until the probe
    /// answers, so the UI never flashes location affordances on and back off, and
    /// the probe clears the latch even when no GPS fix will arrive (indoors).
    public func retryIfLocationServicesDenied() {
        guard locationServicesDenied, isPerAppAuthorized else { return }
        refreshLocationServicesEnabled()
    }

    @available(iOS 14, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status from the injected manager, not from `manager`, so the
        // path under test is the path that ships.
        //
        // Clear the latch only when the transition crosses *into* authorization:
        // a fresh grant (e.g. `.notDetermined`/`.denied` → `.authorizedWhenInUse`)
        // is genuinely new evidence, so re-arm optimistically. A change between two
        // authorized values (WhenInUse → Always) does *not* cross in, so it can't
        // clear a latch while services are still off — that would flicker the
        // locate button and user dot. The system-wide toggle, which delivers no
        // authorization callback at all, is handled by the off-main probe below.
        let newStatus = locationManager.authorizationStatus
        let crossesIntoAuthorization = !rawAuthorizationStatus.isAuthorized && newStatus.isAuthorized
        applyAuthorizationState(rawStatus: newStatus, servicesDenied: crossesIntoAuthorization ? false : locationServicesDenied)

        // Reconcile the latch against the system-wide switch. Core Location fires
        // this callback the moment the delegate is assigned, so this is also where
        // a latch seeded from the previous launch — or a fresh, services-off
        // authorization — is resolved, without waiting for a foreground event.
        refreshLocationServicesEnabled()

        // Accuracy can change while the coarse status stays put (e.g. "Allow
        // Once" elevates a reduced-accuracy session to full). That leaves the
        // effective `authorizationStatus` unchanged, so detect and forward the
        // accuracy transition on its own channel — reading from the injected
        // manager, for the same testability reason as the status above.
        let newAccuracy = locationManager.accuracyAuthorization
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

        // A requested fix is delivered as-is: the prune below exists for
        // continuous streams, where a coarse reading trailing a fine one is
        // noise. Here somebody asked for exactly this reading.
        if !pendingOneShotRequests.isEmpty {
            self.currentLocation = newLocation
            resolveOneShotRequests(with: newLocation)
            return
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
        // `authorizationStatus` to `.denied`, which stops updates (the funnel
        // reconciles the manager down, as Apple recommends) and lets the UI
        // explain the situation.
        //
        // Only latch while the app is itself authorized. A `denied` error that
        // arrives while the raw status is `.denied`/`.notDetermined` would be
        // masked by `authorizationStatus` anyway, but persisting it there means a
        // later grant (made while the app wasn't running) launches with a stale
        // latch that no status-change callback clears — the app would wrongly show
        // "Location Services Off" until a fix happened to arrive.
        if let clError = error as? CLError, clError.code == .denied, isPerAppAuthorized {
            applyAuthorizationState(rawStatus: rawAuthorizationStatus, servicesDenied: true)
        }

        failOneShotRequests(with: error)
        notifyDelegatesErrorReceived(error)
    }
}
