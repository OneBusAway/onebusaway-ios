//
//  LocationService.swift
//  OBALocationKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public class LocationService: NSObject, CLLocationManagerDelegate {
    private var locationManager: LocationManager
    private var notificationCenter: NotificationCenter

    public private(set) var currentLocation: CLLocation?
    public private(set) var currentHeading: CLHeading?

    public convenience override init() {
        self.init(locationManager: CLLocationManager(), notificationCenter: NotificationCenter.default)
    }

    public init(locationManager: LocationManager, notificationCenter: NotificationCenter) {
        self.locationManager = locationManager
        self.notificationCenter = notificationCenter

        super.init()

        self.locationManager.delegate = self
    }

    // MARK: - Notifications

    let AuthorizationStatusChangedNotification = NSNotification.Name(rawValue: "AuthorizationStatusChangedNotification")
    let AuthorizationStatusUserInfoKey = "AuthorizationStatusUserInfoKey"

    let LocationUpdatedNotification = NSNotification.Name(rawValue: "LocationUpdatedNotification")

    let HeadingUpdatedNotification = NSNotification.Name(rawValue: "HeadingUpdatedNotification")
    let HeadingUserInfoKey = "HeadingUserInfoKey"

    let LocationManagerErrorNotification = NSNotification.Name(rawValue: "LocationManagerErrorNotification")
    let LocationErrorUserInfoKey = "LocationErrorUserInfoKey"

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
        return type(of: locationManager).locationServicesEnabled() &&
               (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
    }

    public var isAwaitingAuthorization: Bool {
        return authorizationStatus == .notDetermined
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
        let userInfo = [AuthorizationStatusUserInfoKey: status]
        notificationCenter.post(name: AuthorizationStatusChangedNotification, object: self, userInfo: userInfo)

        if isLocationServicesEnabled {
            startUpdates()
        }
    }

    private let kSuccessiveLocationComparisonWindow = 3.0

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
            return
        }

        // We have this issue where we get a high-accuracy location reading immediately
        // followed by a low-accuracy location reading, such as if wifi-localization
        // completed before cell-tower-localization.  We want to ignore the low-accuracy
        // reading.
        if let currentLocation = currentLocation {
            let interval = newLocation.timestamp.timeIntervalSince(currentLocation.timestamp)

            if interval < kSuccessiveLocationComparisonWindow && currentLocation.horizontalAccuracy < newLocation.horizontalAccuracy {
                print("Pruning location reading with low accuracy.")
                return
            }
        }

        currentLocation = newLocation

        notificationCenter.post(name: LocationUpdatedNotification, object: self)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // abxoxo - check accuracy?
        currentHeading = newHeading
        notificationCenter.post(name: HeadingUpdatedNotification, object: self, userInfo: [HeadingUserInfoKey: newHeading])
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        notificationCenter.post(name: LocationManagerErrorNotification, object: self, userInfo: [LocationErrorUserInfoKey: error])
    }
}
