//
//  LocationServiceMocks.swift
//  OBALocationKitTests
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import OBALocationKit
import OBATestHelpers

class LocDelegate: NSObject, LocationServiceDelegate {
    var location: CLLocation?
    var heading: CLHeading?
    var status: CLAuthorizationStatus?
    var error: Error?

    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        self.location = location
    }

    func locationService(_ service: LocationService, headingChanged heading: CLHeading) {
        self.heading = heading
    }

    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        self.status = status
    }

    func locationService(_ service: LocationService, errorReceived error: Error) {
        self.error = error
    }
}
