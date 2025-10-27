//
//  LocationManagerProtocol.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public protocol LocationManager {
    var delegate: CLLocationManagerDelegate? { get set }

    // MARK: - Authorization

    func requestWhenInUseAuthorization()

    @available(iOS 14, *)
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String)

    /// Replaces the CLLocationManager class func of the same name. This is used
    /// to facilitate easier testing on a per-instance basis instead of having
    /// to try to mock class functions.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Replaces the CLLocationManager class func of the same name. This is used
    /// to facilitate easier testing on a per-instance basis instead of having
    /// to try to mock class functions.
    var isLocationServicesEnabled: Bool { get }

    @available(iOS 14, *)
    var accuracyAuthorization: CLAccuracyAuthorization { get }

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

    public var isLocationServicesEnabled: Bool {
        return CLLocationManager.locationServicesEnabled()
    }

    public var isHeadingAvailable: Bool {
        return CLLocationManager.headingAvailable()
    }
}
