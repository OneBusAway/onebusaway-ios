//
//  LocationService.swift
//  OBALocationKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBALocationServiceDelegate)
public protocol LocationServiceDelegate: NSObjectProtocol {
    @objc optional func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus)
    @objc optional func locationService(_ service: LocationService, locationChanged location: CLLocation)
    @objc optional func locationService(_ service: LocationService, headingChanged heading: CLHeading)
    @objc optional func locationService(_ service: LocationService, errorReceived error: Error)
}

@objc(OBALocationService)
public class LocationService: NSObject, CLLocationManagerDelegate {
    private var locationManager: LocationManager

    public private(set) var currentLocation: CLLocation? {
        didSet {
            if let currentLocation = currentLocation {
                notifyDelegatesLocationChanged(currentLocation)
            }
        }
    }
    public private(set) var currentHeading: CLHeading? {
        didSet {
            if let currentHeading = currentHeading {
                notifyDelegatesHeadingChanged(currentHeading)
            }
        }
    }

    @objc public convenience override init() {
        self.init(locationManager: CLLocationManager())
    }

    @objc public init(locationManager: LocationManager) {
        self.locationManager = locationManager
        self.authorizationStatus = type(of: locationManager).authorizationStatus()

        super.init()

        self.locationManager.delegate = self
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<LocationServiceDelegate>.weakObjects()

    @objc
    public func addDelegate(_ delegate: LocationServiceDelegate) {
        delegates.add(delegate)
    }

    @objc
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

    private func notifyDelegatesHeadingChanged(_ heading: CLHeading) {
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

    /// The current authorization state of the app.
    @objc
    public private(set) var authorizationStatus: CLAuthorizationStatus {
        didSet {
            guard authorizationStatus != oldValue else {
                return
            }

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
    @objc
    public var canRequestAuthorization: Bool {
        return authorizationStatus == .notDetermined
    }

    /// Prompts the user for permission to access location services. (e.g. GPS.)
    @objc
    public func requestInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Answers the question of whether the device GPS can be consulted for location data.
    @objc
    public var isLocationUseAuthorized: Bool {
        return type(of: locationManager).locationServicesEnabled() && authorizationStatus == .authorizedWhenInUse
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
        guard type(of: locationManager).headingAvailable() else {
            return
        }

        locationManager.startUpdatingHeading()
    }

    public func stopUpdatingHeading() {
        guard type(of: locationManager).headingAvailable() else {
            return
        }

        locationManager.stopUpdatingHeading()
    }

    // MARK: - Delegate

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }

    private let kSuccessiveLocationComparisonWindow = 3.0

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
        if interval < kSuccessiveLocationComparisonWindow && currentLocation.horizontalAccuracy < newLocation.horizontalAccuracy {
            print("Pruning location reading with low accuracy.")
            return
        }

        self.currentLocation = newLocation
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // abxoxo - check accuracy?
        currentHeading = newHeading
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        notifyDelegatesErrorReceived(error)
    }
}
