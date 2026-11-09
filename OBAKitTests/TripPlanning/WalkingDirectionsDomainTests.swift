//
//  WalkingDirectionsDomainTests.swift
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

/// Tests for `WalkingDirections.travelTime` calculation edge cases,
/// zero distance, negative or zero velocities, and nil endpoints.
@Suite(.serialized)
final class WalkingDirectionsDomainTests: OBATestCase {

    private let seattleLibrary = CLLocation(latitude: 47.6062, longitude: -122.3321)
    private let westlakeCenter = CLLocation(latitude: 47.6115, longitude: -122.3370)

    // MARK: - Nil Locations

    @Test func `travelTime returns nil when from location is nil`() {
        let time = WalkingDirections.travelTime(from: nil, to: westlakeCenter)
        #expect(time == nil)
    }

    @Test func `travelTime returns nil when to location is nil`() {
        let time = WalkingDirections.travelTime(from: seattleLibrary, to: nil)
        #expect(time == nil)
    }

    @Test func `travelTime returns nil when both locations are nil`() {
        let time = WalkingDirections.travelTime(from: nil, to: nil)
        #expect(time == nil)
    }

    // MARK: - Velocity Edge Cases

    @Test func `travelTime returns nil when velocity is zero`() {
        let time = WalkingDirections.travelTime(from: seattleLibrary, to: westlakeCenter, velocity: 0)
        #expect(time == nil)
    }

    @Test func `travelTime returns nil when velocity is negative`() {
        let time = WalkingDirections.travelTime(from: seattleLibrary, to: westlakeCenter, velocity: -1.5)
        #expect(time == nil)
    }

    // MARK: - Travel Time Calculations

    @Test func `travelTime is zero when start and end coordinates are identical`() {
        let time = WalkingDirections.travelTime(from: seattleLibrary, to: seattleLibrary)
        #expect(time != nil)
        #expect(time == 0.0)
    }

    @Test func `travelTime computes expected duration with default human walking speed`() {
        let distance = seattleLibrary.distance(from: westlakeCenter)
        let expectedTime = distance / WalkingSpeed.defaultMetersPerSecond

        let calculatedTime = WalkingDirections.travelTime(from: seattleLibrary, to: westlakeCenter)

        #expect(calculatedTime != nil)
        if let calculatedTime {
            #expect(abs(calculatedTime - expectedTime) < 0.001)
        }
    }

    @Test func `travelTime scales inversely with custom velocity`() {
        let normalTime = WalkingDirections.travelTime(from: seattleLibrary, to: westlakeCenter, velocity: 1.0)
        let doubleSpeedTime = WalkingDirections.travelTime(from: seattleLibrary, to: westlakeCenter, velocity: 2.0)

        #expect(normalTime != nil)
        #expect(doubleSpeedTime != nil)
        if let normalTime, let doubleSpeedTime {
            #expect(abs(normalTime - (doubleSpeedTime * 2.0)) < 0.01)
        }
    }
}
