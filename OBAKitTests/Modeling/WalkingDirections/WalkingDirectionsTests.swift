//
//  WalkingDirectionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class WalkingDirectionsTests {

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

    @Test func `Travel time default velocity`() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB)
        #expect(time != nil)
        expectClose(time, knownDistance / WalkingSpeed.defaultMetersPerSecond, within: 0.01)
    }

    // MARK: - Custom Velocity

    @Test func `Travel time custom velocity`() {
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

    @Test func `Travel time nil from location`() {
        let time = WalkingDirections.travelTime(from: nil, to: locationB)
        #expect(time == nil)
    }

    @Test func `Travel time nil to location`() {
        let time = WalkingDirections.travelTime(from: locationA, to: nil)
        #expect(time == nil)
    }

    @Test func `Travel time both nil`() {
        let time = WalkingDirections.travelTime(from: nil, to: nil)
        #expect(time == nil)
    }

    // MARK: - Invalid Velocity

    @Test func `Travel time zero velocity returns nil`() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: 0)
        #expect(time == nil)
    }

    @Test func `Travel time negative velocity returns nil`() {
        let time = WalkingDirections.travelTime(from: locationA, to: locationB, velocity: -1.5)
        #expect(time == nil)
    }
}
