//
//  TripSuggestionMatcherTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TripSuggestionMatcherTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Pine St at 3rd Ave, Seattle.
    private let origin = CLLocationCoordinate2D(latitude: 47.6105, longitude: -122.3393)

    private func rider(at coordinate: CLLocationCoordinate2D? = nil, speed: Double = 10, course: Double = 0) -> RiderSample {
        RiderSample(coordinate: coordinate ?? origin, speed: speed, course: course, timestamp: now)
    }

    private func point(_ meters: Double, bearing: Double, from start: CLLocationCoordinate2D? = nil) -> CLLocationCoordinate2D {
        TripSuggestionMatcher.coordinate(from: start ?? origin, distance: meters, bearing: bearing)
    }

    // MARK: - Geometry

    @Test(arguments: zip([0.0, 90, 180, 270, 45], [90.0, 0, 270, 180, 45]))
    func `OBA orientation becomes a compass heading`(orientation: Double, compass: Double) {
        #expect(TripSuggestionMatcher.compassHeading(fromOBAOrientation: orientation) == compass)
    }

    @Test func `an orientation of 0 or none means no heading`() {
        #expect(VehicleSighting.heading(fromLastKnownOrientation: 0) == nil)
        #expect(VehicleSighting.heading(fromLastKnownOrientation: nil) == nil)
        #expect(VehicleSighting.heading(fromLastKnownOrientation: .nan) == nil)
        #expect(VehicleSighting.heading(fromLastKnownOrientation: 90) == 0)
    }

    @Test func `invalid speed and course fall back to the earlier sample's`() {
        let earlier = rider(speed: 9, course: 30)
        let later = RiderSample(coordinate: origin, speed: -1, course: -1, timestamp: now).fillingMotion(from: earlier)
        #expect(later.speed == 9)
        #expect(later.course == 30)
        let valid = RiderSample(coordinate: origin, speed: 4, course: 10, timestamp: now).fillingMotion(from: earlier)
        #expect(valid.speed == 4)
        #expect(valid.course == 10)
    }

    @Test func `heading difference wraps around north`() {
        #expect(TripSuggestionMatcher.headingDifference(350, 10) == 20)
        #expect(TripSuggestionMatcher.headingDifference(10, 350) == 20)
        #expect(TripSuggestionMatcher.headingDifference(0, 180) == 180)
        #expect(TripSuggestionMatcher.headingDifference(-90, 270) == 0)
    }

    @Test func `projected coordinate lands the given distance away`() {
        let target = point(500, bearing: 90)
        // Spherical projection against Core Location's ellipsoidal distance: within 0.5%.
        #expect(abs(origin.distance(from: target) - 500) < 2.5)
        #expect(abs(TripSuggestionMatcher.bearing(from: origin, to: target) - 90) < 0.5)
    }

    // MARK: - Estimation

    @Test func `a stale fix of the rider's own bus is carried up to the rider`() throws {
        // Reported 70 s ago, 700 m behind a rider doing 10 m/s north.
        let sighting = VehicleSighting(coordinate: point(700, bearing: 180), fixTime: now.addingTimeInterval(-70), heading: 0)
        let distance = TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider())
        #expect(try #require(distance) < 5)
    }

    @Test func `the same raw fix with no estimate would be out of range`() {
        let sighting = VehicleSighting(coordinate: point(700, bearing: 180), fixTime: now, heading: 0)
        #expect(TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider()) == nil)
    }

    @Test func `projection is capped`() throws {
        let sighting = VehicleSighting(coordinate: origin, fixTime: now.addingTimeInterval(-170), heading: nil)
        let estimate = try #require(TripSuggestionMatcher.estimatedCoordinate(of: sighting, rider: rider()))
        #expect(abs(origin.distance(from: estimate) - 1200) < 2)
    }

    @Test func `a fix newer than the rider's reading is moved back to it`() throws {
        // The bus reported 10 s after the rider's last fix, 100 m further north.
        let sighting = VehicleSighting(coordinate: point(100, bearing: 0), fixTime: now.addingTimeInterval(10), heading: 0)
        let estimate = try #require(TripSuggestionMatcher.estimatedCoordinate(of: sighting, rider: rider()))
        #expect(estimate.distance(from: origin) < 2)
    }

    @Test func `a fix older than three minutes says nothing`() {
        let sighting = VehicleSighting(coordinate: origin, fixTime: now.addingTimeInterval(-181), heading: 0)
        #expect(TripSuggestionMatcher.estimatedCoordinate(of: sighting, rider: rider()) == nil)
    }

    @Test func `a stopped rider leaves the fix where it is`() throws {
        let sighting = VehicleSighting(coordinate: origin, fixTime: now.addingTimeInterval(-60), heading: 0)
        let estimate = try #require(TripSuggestionMatcher.estimatedCoordinate(of: sighting, rider: rider(speed: 0)))
        #expect(origin.distance(from: estimate) < 0.01)
    }

    // MARK: - Candidates

    @Test func `a bus heading across the rider's path is not a candidate`() {
        let sighting = VehicleSighting(coordinate: origin, fixTime: now, heading: 90)
        #expect(TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider(course: 0)) == nil)
    }

    @Test func `a bus within 45 degrees is a candidate`() {
        let sighting = VehicleSighting(coordinate: point(50, bearing: 0), fixTime: now, heading: 40)
        #expect(TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider(course: 0)) != nil)
    }

    @Test func `no heading from either side skips the heading check`() {
        let sighting = VehicleSighting(coordinate: point(50, bearing: 0), fixTime: now, heading: nil)
        #expect(TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider(course: -1)) != nil)
    }

    @Test func `a bus 400 m away is not a candidate`() {
        let sighting = VehicleSighting(coordinate: point(400, bearing: 90), fixTime: now, heading: 0)
        #expect(TripSuggestionMatcher.candidateDistance(of: sighting, rider: rider()) == nil)
    }

    // MARK: - Confirmation

    @Test func `a bus still alongside is confirmed`() {
        let earlier = VehicleSighting(coordinate: point(200, bearing: 180), fixTime: now.addingTimeInterval(-40), heading: 0)
        let later = VehicleSighting(coordinate: point(20, bearing: 180), fixTime: now.addingTimeInterval(-2), heading: 0)
        #expect(TripSuggestionMatcher.confirmedDistance(of: later, earlier: earlier, rider: rider()) != nil)
    }

    @Test func `a bus that fell behind is not confirmed`() {
        let later = VehicleSighting(coordinate: point(300, bearing: 180), fixTime: now, heading: 0)
        #expect(TripSuggestionMatcher.confirmedDistance(of: later, earlier: nil, rider: rider()) == nil)
    }

    @Test func `a bus that moved across the rider's course is not confirmed`() {
        // Near the rider both times, but it travelled east while the rider went north.
        let earlier = VehicleSighting(coordinate: point(60, bearing: 270), fixTime: now.addingTimeInterval(-20), heading: nil)
        let later = VehicleSighting(coordinate: point(60, bearing: 90), fixTime: now, heading: nil)
        #expect(TripSuggestionMatcher.confirmedDistance(of: later, earlier: earlier, rider: rider(speed: 0)) == nil)
    }

    @Test func `the same fix twice is judged on distance alone`() {
        let sighting = VehicleSighting(coordinate: point(30, bearing: 90), fixTime: now, heading: nil)
        #expect(TripSuggestionMatcher.confirmedDistance(of: sighting, earlier: sighting, rider: rider(speed: 0)) != nil)
    }
}
