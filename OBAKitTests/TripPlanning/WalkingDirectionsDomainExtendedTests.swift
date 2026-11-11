//
//  WalkingDirectionsDomainExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended edge-case tests for `WalkingDirections` travel time estimation,
/// extreme distance values, and velocity thresholds.
@Suite(.serialized)
final class WalkingDirectionsDomainExtendedTests: OBATestCase {

    private let origin = CLLocation(latitude: 47.6062, longitude: -122.3321) // Seattle
    private let destination = CLLocation(latitude: 47.6101, longitude: -122.3421) // Pike Place

    // MARK: - Extreme Velocities

    @Test func `travelTime with very low positive velocity calculates large but finite duration`() {
        let tinyVelocity = 0.001 // 1 mm/s
        let time = WalkingDirections.travelTime(from: origin, to: destination, velocity: tinyVelocity)

        #expect(time != nil)
        if let time {
            #expect(time.isFinite)
            #expect(time > 100_000)
        }
    }

    @Test func `travelTime with very high velocity calculates very short duration`() {
        let fastVelocity = 100.0 // 100 m/s
        let time = WalkingDirections.travelTime(from: origin, to: destination, velocity: fastVelocity)

        #expect(time != nil)
        if let time {
            #expect(time < 20.0)
            #expect(time > 0.0)
        }
    }

    @Test func `travelTime returns nil when velocity is NaN or Infinite`() {
        #expect(WalkingDirections.travelTime(from: origin, to: destination, velocity: Double.nan) == nil)
        #expect(WalkingDirections.travelTime(from: origin, to: destination, velocity: Double.infinity) == nil)
        #expect(WalkingDirections.travelTime(from: origin, to: destination, velocity: -Double.infinity) == nil)
    }

    // MARK: - Distance Proximity

    @Test func `travelTime for sub-meter distance returns small fractional seconds`() {
        let nearOrigin = CLLocation(latitude: 47.6062001, longitude: -122.3321001)
        let time = WalkingDirections.travelTime(from: origin, to: nearOrigin)

        #expect(time != nil)
        if let time {
            #expect(time >= 0.0)
            #expect(time < 1.0)
        }
    }

    @Test func `travelTime symmetry between from and to locations`() {
        let forwardTime = WalkingDirections.travelTime(from: origin, to: destination)
        let backwardTime = WalkingDirections.travelTime(from: destination, to: origin)

        #expect(forwardTime != nil)
        #expect(backwardTime != nil)
        if let forwardTime, let backwardTime {
            #expect(abs(forwardTime - backwardTime) < 0.001)
        }
    }
}
