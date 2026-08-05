//
//  TripShapeSplitTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
@testable import OBAKit

@Suite(.serialized)
struct TripShapeSplitTests {

    /// A straight run east along a parallel — constant latitude, evenly spaced
    /// longitudes.
    ///
    /// Deliberately *not* a run north along a meridian: the earth is an
    /// ellipsoid, so equal latitude steps are not equal distances, and a test
    /// built on one cannot say where a given fraction of the line falls. Along a
    /// parallel, equal longitude steps are equal distances, which is what lets
    /// these tests name the expected split point instead of approximating it.
    private func parallel(from startLon: Double, to endLon: Double, points: Int) -> [CLLocationCoordinate2D] {
        precondition(points >= 2)
        return (0..<points).map { index in
            let t = Double(index) / Double(points - 1)
            return CLLocationCoordinate2D(latitude: 47, longitude: startLon + (endLon - startLon) * t)
        }
    }

    private func expectClose(_ actual: CLLocationCoordinate2D, _ expected: CLLocationCoordinate2D, _ comment: Comment? = nil) {
        #expect(abs(actual.latitude - expected.latitude) < 0.00001, comment)
        #expect(abs(actual.longitude - expected.longitude) < 0.00001, comment)
    }

    // MARK: - Fraction

    @Test func `Fraction is progress over the trip's total distance`() {
        #expect(TripShapeSplit.fraction(distanceAlongTrip: 250, totalDistanceAlongTrip: 1000) == 0.25)
    }

    @Test func `A zero total distance yields no fraction rather than dividing by zero`() {
        #expect(TripShapeSplit.fraction(distanceAlongTrip: 250, totalDistanceAlongTrip: 0) == nil)
        #expect(TripShapeSplit.fraction(distanceAlongTrip: 250, totalDistanceAlongTrip: -1) == nil)
    }

    @Test func `Progress beyond either end of the trip clamps into range`() {
        #expect(TripShapeSplit.fraction(distanceAlongTrip: 2000, totalDistanceAlongTrip: 1000) == 1)
        #expect(TripShapeSplit.fraction(distanceAlongTrip: -50, totalDistanceAlongTrip: 1000) == 0)
    }

    // MARK: - Splitting

    @Test func `Splitting mid-segment interpolates a shared join point`() {
        let line = parallel(from: -122, to: -121.99, points: 2)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 0.5)

        #expect(result.spent.count == 2)
        #expect(result.ahead.count == 2)
        expectClose(result.spent[0], line[0])
        expectClose(result.ahead[1], line[1])

        // The join is one point shared by both halves, so the two overlays meet
        // exactly instead of leaving a gap at the vehicle.
        let join = CLLocationCoordinate2D(latitude: 47, longitude: -121.995)
        expectClose(result.spent[1], join, "spent should end at the split point")
        expectClose(result.ahead[0], join, "ahead should start at the split point")
    }

    @Test func `Splitting on a vertex keeps that vertex in both halves`() {
        let line = parallel(from: -122, to: -121.98, points: 3)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 0.5)

        #expect(result.spent.count == 2)
        #expect(result.ahead.count == 2)
        expectClose(result.spent[1], line[1])
        expectClose(result.ahead[0], line[1])
    }

    /// A cut landing on a vertex must reuse that vertex, not lay an interpolated
    /// copy on top of it. Duplicate consecutive points are a zero-length segment
    /// in the `MKPolyline` the layer builds from these arrays.
    @Test func `A cut on a vertex leaves no duplicated point`() {
        let line = parallel(from: -122, to: -121.98, points: 3)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 0.5)

        for half in [result.spent, result.ahead] {
            for (a, b) in zip(half, half.dropFirst()) {
                #expect(!(abs(a.latitude - b.latitude) < 1e-12 && abs(a.longitude - b.longitude) < 1e-12),
                        "consecutive points should never coincide")
            }
        }
    }

    @Test func `Every vertex behind the split stays in the spent half`() {
        let line = parallel(from: -122, to: -121.96, points: 5)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 0.75)

        // Four vertices at or behind 75%, plus the split point that coincides
        // with the fourth.
        #expect(result.spent.count == 4)
        #expect(result.ahead.count == 2)
        expectClose(result.spent.last!, line[3])
    }

    @Test func `A trip that has not started leaves nothing spent`() {
        let line = parallel(from: -122, to: -121.99, points: 4)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 0)

        #expect(result.spent.isEmpty)
        #expect(result.ahead.count == 4)
    }

    @Test func `A finished trip leaves nothing ahead`() {
        let line = parallel(from: -122, to: -121.99, points: 4)
        let result = TripShapeSplit.split(coordinates: line, atFraction: 1)

        #expect(result.spent.count == 4)
        #expect(result.ahead.isEmpty)
    }

    @Test func `A fraction outside the unit range clamps instead of overrunning`() {
        let line = parallel(from: -122, to: -121.99, points: 4)

        #expect(TripShapeSplit.split(coordinates: line, atFraction: -3).spent.isEmpty)
        #expect(TripShapeSplit.split(coordinates: line, atFraction: 4).ahead.isEmpty)
    }

    // MARK: - Degenerate input

    @Test func `A shape too short to draw splits into nothing`() {
        let single = [CLLocationCoordinate2D(latitude: 47, longitude: -122)]

        #expect(TripShapeSplit.split(coordinates: [], atFraction: 0.5).spent.isEmpty)
        #expect(TripShapeSplit.split(coordinates: [], atFraction: 0.5).ahead.isEmpty)
        #expect(TripShapeSplit.split(coordinates: single, atFraction: 0.5).spent.isEmpty)
        #expect(TripShapeSplit.split(coordinates: single, atFraction: 0.5).ahead.isEmpty)
    }

    /// A shape whose points are all identical has no length to measure progress
    /// against. Splitting it must not divide by zero — and since no part of it
    /// can be meaningfully called travelled, it all counts as ahead.
    @Test func `A zero-length shape is entirely ahead`() {
        let stationary = Array(repeating: CLLocationCoordinate2D(latitude: 47, longitude: -122), count: 3)
        let result = TripShapeSplit.split(coordinates: stationary, atFraction: 0.5)

        #expect(result.spent.isEmpty)
        #expect(result.ahead.count == 3)
    }
}
