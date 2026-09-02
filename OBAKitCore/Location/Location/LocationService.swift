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

    private func notifyDelegatesMonitoringDidFail(_ identifier: String?, error: Error, kind: RegionMonitoringFailureKind) {
        for delegate in delegates.allObjects {
            delegate.locationService?(self, monitoringDidFailFor: identifier, error: error, kind: kind)
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
            startUpdates()
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

    /// Prompts the user to upgrade to Always authorization, which region
    /// monitoring requires to deliver geofence events in the background.
    ///
    /// Apple only surfaces this prompt once, and only from `.authorizedWhenInUse`
    /// or `.notDetermined` — calling it from `.denied` or `.restricted` does
    /// nothing at all. Callers should therefore treat it as a one-shot upgrade
    /// path and fall back to deep-linking Settings when it no-ops.
    ///
    /// - Important: This also requires `NSLocationAlwaysAndWhenInUseUsageDescription`
    ///   in the host app's Info.plist; without it iOS ignores the call entirely.
    ///   `Apps/Shared/app_shared.yml` declares it for every white-label app, and
    ///   KiedyBus overrides the body with its own. A new app that skips both will
    ///   never reach `.authorizedAlways`, and this method will silently do nothing.
    @objc public func requestAlwaysAuthorization() {
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
    public func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
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

        notifyDelegatesErrorReceived(error)
    }

    // MARK: - Region Monitoring

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
        locationManager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.proximityRegionPrefix) }
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

        // Re-arming an alert already being monitored replaces its region instead
        // of adding one — `CLRegion` hashes on identifier — so it can't push the
        // app over the cap and must not be rejected by this check.
        let isReplacement = locationManager.monitoredRegions.contains { $0.identifier == identifier }
        if !isReplacement, locationManager.monitoredRegions.count >= Self.maximumMonitoredRegions {
            Logger.warn("Not monitoring proximity alert \(alert.id): already at the \(Self.maximumMonitoredRegions)-region limit.")
            return .regionLimitReached(limit: Self.maximumMonitoredRegions)
        }

        // `CLCircularRegion` clamps an oversize radius without reporting it, so
        // the alert would fire at a distance the user never chose. Clamp
        // deliberately and say so. A non-positive device maximum means the value
        // is unavailable rather than zero, so honor the request in that case.
        let requestedRadius = alert.radiusMeters
        let deviceMaximum = locationManager.maximumRegionMonitoringDistance
        let radius = deviceMaximum > 0 ? min(requestedRadius, deviceMaximum) : requestedRadius

        let region = CLCircularRegion(center: alert.coordinate, radius: radius, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        locationManager.startMonitoring(for: region)

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
        guard let matchingRegion = locationManager.monitoredRegions.first(where: {
            $0.identifier == identifier
        }) else {
            Logger.warn("No monitored region found for proximity alert \(id)")
            return
        }
        locationManager.stopMonitoring(for: matchingRegion)
    }

    /// Stops monitoring all proximity alert regions without affecting other monitored regions.
    public func stopMonitoringAllProximityAlerts() {
        for region in monitoredProximityRegions {
            locationManager.stopMonitoring(for: region)
        }
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

        Logger.error("Region monitoring failed for proximity region \(identifier) (\(kind)): \(error)")
        notifyDelegatesMonitoringDidFail(identifier, error: error, kind: kind)
    }
}
