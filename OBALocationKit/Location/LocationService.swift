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
    @objc optional func authorizationStatusChanged(_ status: CLAuthorizationStatus)
    @objc optional func locationChanged(_ location: CLLocation)
    @objc optional func headingChanged(_ heading: CLHeading)
    @objc optional func errorReceived(_ error: Error)
}

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

    public convenience override init() {
        self.init(locationManager: CLLocationManager())
    }

    public init(locationManager: LocationManager) {
        self.locationManager = locationManager

        super.init()

        self.locationManager.delegate = self
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
            delegate.authorizationStatusChanged?(status)
        }
    }

    private func notifyDelegatesLocationChanged(_ location: CLLocation) {
        for delegate in delegates.allObjects {
            delegate.locationChanged?(location)
        }
    }

    private func notifyDelegatesHeadingChanged(_ heading: CLHeading) {
        for delegate in delegates.allObjects {
            delegate.headingChanged?(heading)
        }
    }

    private func notifyDelegatesErrorReceived(_ error: Error) {
        for delegate in delegates.allObjects {
            delegate.errorReceived?(error)
        }
    }

    // MARK: - Authorization

    public func requestInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    public var hasRequestedLocationAuthorization: Bool {
        return authorizationStatus != .notDetermined
    }

    public var authorizationStatus: CLAuthorizationStatus {
        return type(of: locationManager).authorizationStatus()
    }

    public var isLocationServicesEnabled: Bool {
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
        guard isLocationServicesEnabled else {
            return
        }

        locationManager.startUpdatingLocation()
    }

    public func stopUpdatingLocation() {
        guard isLocationServicesEnabled else {
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
        notifyDelegatesAuthorizationChanged(status)

        if isLocationServicesEnabled {
            startUpdates()
        }
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
