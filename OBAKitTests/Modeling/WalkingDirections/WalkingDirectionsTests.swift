//
//  WalkingDirectionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit

class WalkingDirectionsTests: XCTestCase {

    // Two locations exactly 140 meters apart
    private let locationA = CLLocation(latitude: 47.6062, longitude: -122.3321)
    private lazy var locationB: CLLocation = {
        // Shift north by ~140m (approx 0.00126 degrees latitude)
        CLLocation(latitude: locationA.coordinate.latitude + 0.00126, longitude: locationA.coordinate.longitude)
    }()

    private var knownDistance: Double {
        locationA.distance(from: locationB)
    }

    // MARK: - Default Velocity

    func test_travelTime_defaultVelocity() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB)
        expect(time).toNot(beNil())
        expect(time).to(beCloseTo(knownDistance / 1.4, within: 0.01))
    }

    // MARK: - Custom Velocity

    func test_travelTime_customVelocity() {
        let slowTime = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 0.9)
        let fastTime = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 1.8)

        expect(slowTime).toNot(beNil())
        expect(fastTime).toNot(beNil())
        expect(slowTime).to(beCloseTo(knownDistance / 0.9, within: 0.01))
        expect(fastTime).to(beCloseTo(knownDistance / 1.8, within: 0.01))

        // Slower speed should yield a longer travel time
        expect(slowTime!) > fastTime!
    }

    // MARK: - Nil Locations

    func test_travelTime_nilFromLocation() {
        let time = WalkingDirections.travelTime(from: nil, to: locationB)
        expect(time).to(beNil())
    }

    func test_travelTime_nilToLocation() {
        let time = WalkingDirections.travelTime(from: locationA, to: nil)
        expect(time).to(beNil())
    }

    func test_travelTime_bothNil() {
        let time = WalkingDirections.travelTime(from: nil, to: nil)
        expect(time).to(beNil())
    }
}
