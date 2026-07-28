//
//  WalkingDirectionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
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
        #expect(time != nil)
        expectClose(time, knownDistance / WalkingSpeed.defaultMetersPerSecond, within: 0.01)
    }

    // MARK: - Custom Velocity

    func test_travelTime_customVelocity() {
        let slowTime = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 0.9)
        let fastTime = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 1.8)

        #expect(slowTime != nil)
        #expect(fastTime != nil)
        expectClose(slowTime, knownDistance / 0.9, within: 0.01)
        expectClose(fastTime, knownDistance / 1.8, within: 0.01)

        // Slower speed should yield a longer travel time
        #expect(slowTime! > fastTime!)
    }

    // MARK: - Nil Locations

    func test_travelTime_nilFromLocation() {
        let time = WalkingDirections.travelTime(from: nil, to: locationB)
        #expect(time == nil)
    }

    func test_travelTime_nilToLocation() {
        let time = WalkingDirections.travelTime(from: locationA, to: nil)
        #expect(time == nil)
    }

    func test_travelTime_bothNil() {
        let time = WalkingDirections.travelTime(from: nil, to: nil)
        #expect(time == nil)
    }

    // MARK: - Invalid Velocity

    func test_travelTime_zeroVelocity_returnsNil() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 0)
        #expect(time == nil)
    }

    func test_travelTime_negativeVelocity_returnsNil() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: -1.5)
        #expect(time == nil)
    }
}
