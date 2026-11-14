//
//  TripGeometryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TripGeometryTests {
    typealias F = EstimationFixtures

    /// Servers measure the shape themselves, slightly differently from the decoded
    /// polyline. Stop distances are rescaled onto the shape the map draws.
    @Test func `Stop distances are rescaled onto the client shape`() {
        let geometry = TripGeometry(
            shape: F.straightLine(),
            stopTimes: [F.stop(0, at: 0), F.stop(1000, at: 60), F.stop(2000, at: 120)],
            serverTripLength: 2000
        )
        #expect(geometry.stops.map { ($0.distanceAlongShape * 10).rounded() / 10 } == [0, 500, 1000])
    }

    @Test func `Without a server trip length, the last stop's distance stands in`() {
        let geometry = TripGeometry(shape: F.straightLine(), stopTimes: [F.stop(0, at: 0), F.stop(500, at: 60)], serverTripLength: nil)
        expectClose(geometry.stops.last?.distanceAlongShape, 1000, within: 0.01)
    }

    @Test(arguments: [
        [nil, 500.0],          // a stop without a distance
        [0.0, 600.0, 500.0],   // distances that go backward
        [0.0, 0.0, 0.0]        // maglev's shapeless trip
    ] as [[Double?]])
    func `An unusable schedule yields no stops`(distances: [Double?]) {
        let stopTimes = distances.enumerated().map { index, distance in
            TripGeometry.StopTime(distanceAlongTrip: distance, arrival: F.t0 + Double(index) * 60, departure: F.t0 + Double(index) * 60)
        }
        let geometry = TripGeometry(shape: F.straightLine(), stopTimes: stopTimes, serverTripLength: 1000)
        #expect(geometry.stops.isEmpty)
        #expect(!geometry.hasSchedule)
    }

    @Test func `Scheduled time interpolates linearly between stops`() {
        let geometry = F.tenMetersPerSecond(extraStops: [500])
        expectClose(geometry.scheduledTime(at: 250), 25, within: 0.001)
        expectClose(geometry.scheduledTime(at: 750), 75, within: 0.001)
    }

    @Test func `Scheduled speed is the stop-to-stop pace`() {
        let geometry = TripGeometry(
            shape: F.straightLine(),
            stopTimes: [F.stop(0, at: 0), F.stop(200, at: 40), F.stop(1000, at: 100)],
            serverTripLength: 1000
        )
        expectClose(geometry.scheduledSpeed(at: 100), 5, within: 0.001)
        expectClose(geometry.scheduledSpeed(at: 600), 800.0 / 60, within: 0.001)
    }

    /// GTFS times are often whole minutes, so neighbouring stops can share one. They
    /// merge into one span rather than producing an infinite speed between them.
    @Test func `Stops sharing a scheduled time merge into one span`() {
        let geometry = TripGeometry(
            shape: F.straightLine(),
            stopTimes: [F.stop(0, at: 0), F.stop(100, at: 60), F.stop(200, at: 60), F.stop(1000, at: 120)],
            serverTripLength: 1000
        )
        let speed = geometry.scheduledSpeed(at: 150)
        #expect(speed != nil)
        #expect(speed!.isFinite)
        expectClose(geometry.scheduledSpeed(at: 150), 900.0 / 60, within: 0.001)
    }

    @Test func `A trip with no schedule has no scheduled speed`() {
        let geometry = TripGeometry(shape: F.straightLine(), stopTimes: [], serverTripLength: 1000)
        #expect(geometry.scheduledSpeed(at: 100) == nil)
        #expect(geometry.scheduledTime(at: 100) == nil)
    }
}
