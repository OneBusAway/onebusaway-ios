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
public protocol LocationServiceDelegate: NSObjectProtocol {
    @objc optional func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus)
    @objc optional func locationService(_ service: LocationService, locationChanged location: CLLocation)
    @objc optional func locationService(_ service: LocationService, headingChanged heading: CLHeading?)
    @objc optional func locationService(_ service: LocationService, errorReceived error: Error)
    @objc optional func locationService(_ service: LocationService, didEnterMonitoredRegion identifier: String)
    @objc optional func locationService(_ service: LocationService, monitoringDidFailFor identifier: String?, error: Error)
}

@objc(OBALocationService) public class LocationService: NSObject, CLLocationManagerDelegate {
    private var locationManager: LocationManager

    public convenience override init() {
        self.init(userDefaults: UserDefaults.standard, locationManager: CLLocationManager())
    }

    public init(userDefaults: UserDefaults, locationManager: LocationManager) {
        self.locationManager = locationManager
        authorizationStatus = locationManager.authorizationStatus
        currentLocation = locationManager.location

        self.userDefaults = userDefaults

        super.init()

        registerDefaults()

        self.locationManager.delegate = self
    }

    // MARK: - User Defaults

    private let userDefaults: UserDefaults

    private struct UserDefaultsKeys {
        static let promptUserForLocationPermission = "LocationService.promptUserForLocationPermission"
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

    /// The current authorization state of the app.
    public private(set) var authorizationStatus: CLAuthorizationStatus {
        didSet {
            notifyDelegatesAuthorizationChanged(authorizationStatus)

            if isLocationUseAuthorized {
                startUpdates()
            }
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
    public var isLocationUseAuthorized: Bool {
        return locationManager.isLocationServicesEnabled &&
            (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }

    @available(iOS 14, *)
    public var accuracyAuthorization: CLAccuracyAuthorization {
        return locationManager.accuracyAuthorization
    }

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

    public func stopUpdatingLocation() {
        guard isLocationUseAuthorized else {
            return
        }

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

    @available(iOS, introduced: 4.2, deprecated: 14.0)
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }

    @available(iOS 14, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    public var successiveLocationComparisonWindow: TimeInterval = 60.0

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
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
