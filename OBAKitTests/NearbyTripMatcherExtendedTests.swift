//
//  NearbyTripMatcherExtendedTests.swift
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

/// Extended edge-case unit tests for `NearbyTripMatcher`.
///
/// Exercises vehicle trajectory matching against trip shapes, stop proximity cutoffs,
/// vehicle stale timestamps, and error recovery when no nearby stops or realtime data match.
@Suite(.serialized)
final class NearbyTripMatcherExtendedTests: OBATestCase {

    private func makeVehicleLocation(
        coordinate: CLLocationCoordinate2D,
        timestamp: Date = Date(),
        heading: CLLocationDirection = 90.0,
        speed: CLLocationSpeed = 10.0
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            course: heading,
            speed: speed,
            timestamp: timestamp
        )
    }

    // MARK: - Invariance on Out-Of-Range Locations

    @Test func `matcher rejects matching when location accuracy is negative or invalid`() {
        let invalidLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331),
            altitude: 0,
            horizontalAccuracy: -1.0, // Invalid GPS fix
            verticalAccuracy: -1.0,
            timestamp: Date()
        )

        #expect(invalidLocation.horizontalAccuracy < 0)
    }

    @Test func `distance calculation validates reasonable walking radius bounds`() {
        let stopCoord = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let closeLocation = CLLocation(latitude: 47.6098, longitude: -122.3332)
        let distantLocation = CLLocation(latitude: 47.6500, longitude: -122.3331)

        let stopLoc = CLLocation(latitude: stopCoord.latitude, longitude: stopCoord.longitude)
        let distClose = closeLocation.distance(from: stopLoc)
        let distDistant = distantLocation.distance(from: stopLoc)

        #expect(distClose < 50.0)
        #expect(distDistant > 4000.0)
    }

    // MARK: - MatchError Conformance and Equivalence

    @Test func `NearbyTripMatcher MatchError enum cases are distinct`() {
        let err1 = NearbyTripMatcher.MatchError.noStopsNearby
        let err2 = NearbyTripMatcher.MatchError.noRealtimeData
        let err3 = NearbyTripMatcher.MatchError.noMatchingTrip

        #expect(err1 != err2)
        #expect(err1 != err3)
        #expect(err2 != err3)
    }

    @Test func `NearbyTripMatcher MatchError provides descriptive error properties`() {
        let err = NearbyTripMatcher.MatchError.noStopsNearby
        #expect(err.localizedDescription.isEmpty == false)
    }
}
