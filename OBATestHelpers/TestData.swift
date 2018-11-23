//
//  TestData.swift
//  OBATestHelpers
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public class TestData: NSObject {

    public static let seattleCoordinate = CLLocationCoordinate2D(latitude: 47.623651, longitude: -122.312572)
    public static let tampaCoordinate = CLLocationCoordinate2D(latitude: 27.976911, longitude: -82.445851)

    public static var mockSeattleLocation: CLLocation = {
        let loc = CLLocation(coordinate: seattleCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())
        return loc
    }()

    public static var mockTampaLocation: CLLocation = {
        let loc = CLLocation(coordinate: tampaCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())
        return loc
    }()

    public static let mockHeading = OBAMockHeading(heading: 45.0)
}
