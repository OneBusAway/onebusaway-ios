//
//  CoreLocationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 1/17/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation
import Nimble
import XCTest
import CoreLocation
@testable import OBAKit

class CoreLocationTests: XCTestCase {

    // MARK: - CLCircularRegion

    func test_creation_fromMapRect() {
        let mapRect = MKMapRect(x: 43013871.99811534, y: 93728205.2278356, width: 1984.0073646754026, height: 3397.6126077622175)
        let region = CLCircularRegion(mapRect: mapRect)

        expect(region.center.latitude).to(beCloseTo(47.62365100))
        expect(region.center.longitude).to(beCloseTo(-122.31257200))
        expect(region.radius).to(beCloseTo(197.86, within: 0.1))
    }

    // MARK: - Distance

    func test_distanceCalculation() {
        let pt1 = CLLocationCoordinate2D(latitude: 47.62365100, longitude: -122.31257200)
        let pt2 = CLLocationCoordinate2D(latitude: 47.632352, longitude: -122.312526)

        let distance = pt1.distance(from: pt2)
        expect(distance).to(beCloseTo(967.4102))
    }
}
