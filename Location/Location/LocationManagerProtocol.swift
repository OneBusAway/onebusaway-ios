//
//  LocationManagerProtocol.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBALocationManager)
public protocol LocationManager {
    var delegate: CLLocationManagerDelegate? { get set }

    // MARK: - Authorization

    func requestWhenInUseAuthorization()

    /// Replaces the CLLocationManager class func of the same name. This is used
    /// to facilitate easier testing on a per-instance basis instead of having
    /// to try to mock class functions.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Replaces the CLLocationManager class func of the same name. This is used
    /// to facilitate easier testing on a per-instance basis instead of having
    /// to try to mock class functions.
    var isLocationServicesEnabled: Bool { get }

    // MARK: - Location

    func startUpdatingLocation()
    func stopUpdatingLocation()
    var location: CLLocation? { get }

    // MARK: - Heading
    var isHeadingAvailable: Bool { get }
    func startUpdatingHeading()
    func stopUpdatingHeading()
}

extension CLLocationManager: LocationManager {
    // nop. CLLocationManager already implements all of the protocol methods.

    public var authorizationStatus: CLAuthorizationStatus {
        return CLLocationManager.authorizationStatus()
    }

    public var isLocationServicesEnabled: Bool {
        return CLLocationManager.locationServicesEnabled()
    }

    public var isHeadingAvailable: Bool {
        return CLLocationManager.headingAvailable()
    }
}
