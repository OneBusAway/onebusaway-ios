//
//  LocationManagerProtocol.swift
//  OBALocationKit
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public protocol LocationManager {
    var delegate: CLLocationManagerDelegate? { get set }

    // MARK: - Authorization

    func requestWhenInUseAuthorization()

    static func authorizationStatus() -> CLAuthorizationStatus
    static func locationServicesEnabled() -> Bool

    // MARK: - Location

    func startUpdatingLocation()
    func stopUpdatingLocation()
    var location: CLLocation? { get }

    // MARK: - Heading
    static func headingAvailable() -> Bool
    func startUpdatingHeading()
    func stopUpdatingHeading()
}

extension CLLocationManager: LocationManager {
    // nop. CLLocationManager already implements all of the protocol methods.
}
