//
//  TripETADistanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit

@Suite(.serialized)
struct TripETADistanceTests {

    private let formatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.units = .imperial
        return formatter
    }()

    private func make(distance: Double, stops: Int, predicted: Bool = true) -> TripETADistance? {
        TripETADistance.make(distanceMeters: distance, stopsAway: stops, isPredicted: predicted, formatter: formatter)
    }

    @Test func `A tracked vehicle shows its distance and stop count`() throws {
        let line = try #require(make(distance: 1931, stops: 3))
        let distance = formatter.string(fromDistance: 1931)

        #expect(line.text == "\(distance) away · 3 stops")
        #expect(line.accessibilityText == "\(distance) away, 3 stops away")
    }

    @Test func `The distance comes from the injected formatter so it follows the rider's units`() throws {
        let line = try #require(make(distance: 1931, stops: 3))

        #expect(line.text.contains("mi"))
        #expect(!line.text.contains("km"))
    }

    @Test func `One stop away reads in the singular`() throws {
        let line = try #require(make(distance: 400, stops: 1))

        #expect(line.text.hasSuffix("· 1 stop"))
        #expect(line.accessibilityText.hasSuffix("1 stop away"))
    }

    /// The server derives `distanceFromStop` for schedule-only trips from where
    /// the schedule says the vehicle should be. Showing that as "1.2 mi away"
    /// would present a guess as a tracked vehicle.
    @Test func `A schedule only trip shows nothing`() {
        #expect(make(distance: 1931, stops: 3, predicted: false) == nil)
    }

    /// Real feeds keep counting past the stop: -1833.69 m with -9 stops.
    @Test func `A vehicle that has passed the stop shows nothing`() {
        #expect(make(distance: -1833.69, stops: -9) == nil)
        #expect(make(distance: -10, stops: 0) == nil)
        #expect(make(distance: 120, stops: -1) == nil)
    }

    @Test func `A vehicle whose next stop is the rider's says it is arriving instead of a distance`() throws {
        let approaching = try #require(make(distance: 350, stops: 0))
        let atStop = try #require(make(distance: 0, stops: 0))

        #expect(approaching.text == "Arriving at your stop")
        #expect(atStop.text == "Arriving at your stop")
        #expect(approaching.accessibilityText == approaching.text)
        #expect(!approaching.text.contains("mi"))
    }

    @Test func `A distance that is not a number shows nothing`() {
        #expect(make(distance: .nan, stops: 3) == nil)
        #expect(make(distance: .infinity, stops: 3) == nil)
    }

    /// The card rebuilds from each refreshed `ArrivalDeparture`; the line must
    /// be a pure function of its inputs, not a value captured once.
    @Test func `New inputs produce a new line`() throws {
        let before = try #require(make(distance: 1931, stops: 3))
        let after = try #require(make(distance: 800, stops: 1))

        #expect(before != after)
        #expect(after.text.hasSuffix("· 1 stop"))
    }
}
