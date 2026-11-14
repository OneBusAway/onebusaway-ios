//
//  VehicleEstimationReplayTests.swift
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

/// The offline evaluation in `docs/vehicle-position-estimation.md` §8.3, over real
/// Puget Sound trips recorded with `scripts/vehicle_replay_fixture`.
///
/// Two measures, each against two baselines: the reported GPS fix, which the trip
/// page draws today, and the server's `position`, which the stop's map draws.
///
/// - **Display error** is what a rider sees. Every 5 s of device time the marker
///   shows whatever was drawn from the fixes received by then; the truth is where
///   the vehicle actually was at that moment, interpolated along the shape between
///   the fixes either side of it, which only arrive later.
/// - **Next-fix error** is the brief's: from the fixes received before a new one
///   arrives, predict where that new one will be at its own fix time.
///
/// The table is printed; the assertions hold the estimator to beating the
/// reported fix on both, which is the claim the feature makes.
@Suite(.serialized)
struct VehicleEstimationReplayTests {

    static let fixtures = [
        "vehicle_replay_1_732749241.json", "vehicle_replay_1_800601251.json",
        "vehicle_replay_1_803817221.json", "vehicle_replay_1_849269501.json",
        "vehicle_replay_1_849270531.json", "vehicle_replay_1_849271061.json",
        "vehicle_replay_1_871704921.json", "vehicle_replay_1_872074691.json"
    ]

    struct Replay: Decodable {
        struct StopTime: Decodable {
            let distanceAlongTrip: Double?
            let arrivalTime: Double
            let departureTime: Double
        }
        struct Observation: Decodable {
            let receivedAt: Double
            let serverTime: Double
            let fixTime: Double
            let lat: Double
            let lon: Double
            let positionLat: Double?
            let positionLon: Double?
            let activeTripId: String?
            let vehicleId: String?
            let predicted: Bool
            let scheduleDeviation: Double
            let totalDistanceAlongTrip: Double?

            var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
            var position: CLLocationCoordinate2D? {
                guard let positionLat, let positionLon else { return nil }
                return .init(latitude: positionLat, longitude: positionLon)
            }
        }
        let route: String
        let tripId: String
        let serviceDate: Double
        let shape: String
        let stopTimes: [StopTime]
        let observations: [Observation]
    }

    struct Errors {
        var estimate: [Double] = []
        var reported: [Double] = []
        var server: [Double] = []

        mutating func append(_ other: Errors) {
            estimate += other.estimate
            reported += other.reported
            server += other.server
        }
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        return sorted[min(Int((Double(sorted.count - 1) * p).rounded()), sorted.count - 1)]
    }

    static func load(_ name: String) throws -> Replay {
        try JSONDecoder().decode(Replay.self, from: Fixtures.loadData(file: name))
    }

    static func geometry(_ replay: Replay) throws -> TripGeometry {
        let coordinates = try #require(Polyline(encodedPolyline: replay.shape).coordinates)
        let shape = try #require(ShapeLine(coordinates: coordinates))
        let serviceDate = Date(timeIntervalSince1970: replay.serviceDate)
        let stops = replay.stopTimes.map {
            TripGeometry.StopTime(distanceAlongTrip: $0.distanceAlongTrip, arrival: serviceDate + $0.arrivalTime, departure: serviceDate + $0.departureTime)
        }
        return TripGeometry(shape: shape, stopTimes: stops, serverTripLength: replay.observations.first?.totalDistanceAlongTrip)
    }

    static func fix(_ observation: Replay.Observation, tripID: String) -> VehicleFix? {
        guard observation.predicted, observation.activeTripId == tripID else { return nil }
        return VehicleFix(
            tripID: tripID,
            vehicleID: observation.vehicleId,
            fixTime: Date(timeIntervalSince1970: observation.fixTime),
            coordinate: observation.coordinate,
            scheduleDeviation: observation.scheduleDeviation
        )
    }

    /// Where the vehicle was at `time` (server clock): interpolated along the shape
    /// between the fixes either side of it, when they are close enough together to
    /// trust the line between them.
    static func truth(at time: Double, fixes: [(time: Double, s: Double)], shape: ShapeLine) -> CLLocationCoordinate2D? {
        guard let after = fixes.firstIndex(where: { $0.time >= time }), after > 0 else { return nil }
        let a = fixes[after - 1], b = fixes[after]
        guard b.time - a.time <= 60, b.s >= a.s else { return nil }
        let s = a.s + (b.s - a.s) * (time - a.time) / max(b.time - a.time, 0.001)
        return shape.point(at: s).coordinate
    }

    static func evaluate(_ replay: Replay) throws -> (display: Errors, nextFix: Errors) {
        let geometry = try geometry(replay)
        let shape = geometry.shape
        let observations = replay.observations.sorted { $0.receivedAt < $1.receivedAt }

        var skew = ClockSkewEstimator()
        observations.forEach { skew.record(ServerClockSample(serverTime: Date(timeIntervalSince1970: $0.serverTime), receivedAt: Date(timeIntervalSince1970: $0.receivedAt))) }
        let offset = skew.deviceOffset

        // Ground truth: every fix, on the shape, in fix-time order.
        var truthFixes: [(time: Double, s: Double)] = []
        for observation in observations.sorted(by: { $0.fixTime < $1.fixTime }) where fix(observation, tripID: replay.tripId) != nil {
            if let projection = shape.project(observation.coordinate, maxOffset: 60, hint: truthFixes.last?.s, maxBackwardJump: 100) {
                truthFixes.append((observation.fixTime, projection.distanceAlongShape))
            }
        }

        var display = Errors(), nextFix = Errors()
        var track = VehicleTrack(geometry: geometry)
        // Fed the same fixes, never displayed: the marker's never-backward clamp
        // would otherwise hold a prediction for an earlier moment at a later spot.
        var predictor = VehicleTrack(geometry: geometry)
        var next = 0
        var previous: Replay.Observation?
        var newestFixTime: Date?

        func ingest(_ observation: Replay.Observation) {
            if let fix = fix(observation, tripID: replay.tripId) {
                // Next-fix error, from a copy so the prediction leaves no trace. Only
                // for a newer fix: a repeat or a late, older one is no prediction.
                if let previous, predictor.hasFix, newestFixTime.map({ fix.fixTime > $0 }) ?? true {
                    var probe = predictor
                    if let predicted = probe.estimate(at: fix.fixTime) {
                        nextFix.estimate.append(predicted.coordinate.distance(from: fix.coordinate))
                        nextFix.reported.append(previous.coordinate.distance(from: fix.coordinate))
                        if let server = previous.position { nextFix.server.append(server.distance(from: fix.coordinate)) }
                    }
                }
                let receivedAt = Date(timeIntervalSince1970: observation.receivedAt - offset)
                _ = track.ingest(fix, now: receivedAt)
                _ = predictor.ingest(fix, now: receivedAt)
                // What the app draws today, even when it is older than the last.
                previous = observation
                newestFixTime = max(newestFixTime ?? fix.fixTime, fix.fixTime)
            }
        }

        guard let start = observations.first?.receivedAt, let end = truthFixes.last?.time else { return (display, nextFix) }
        var deviceTime = start
        while deviceTime - offset <= end {
            while next < observations.count, observations[next].receivedAt <= deviceTime {
                ingest(observations[next])
                next += 1
            }
            let serverTime = deviceTime - offset
            if let previous, let truth = truth(at: serverTime, fixes: truthFixes, shape: shape),
               let shown = track.estimate(at: Date(timeIntervalSince1970: serverTime)) {
                display.estimate.append(shown.coordinate.distance(from: truth))
                display.reported.append(previous.coordinate.distance(from: truth))
                if let server = previous.position { display.server.append(server.distance(from: truth)) }
            }
            deviceTime += 5
        }
        return (display, nextFix)
    }

    static func row(_ label: String, _ errors: [Double]) -> String {
        String(format: "%@ median %6.1f m   p90 %6.1f m   (n=%d)", label.padding(toLength: 22, withPad: " ", startingAt: 0), percentile(errors, 0.5), percentile(errors, 0.9), errors.count)
    }

    @Test func `On recorded trips the estimate is closer to the bus than the reported fix`() throws {
        var display = Errors(), nextFix = Errors()
        for name in Self.fixtures {
            let replay = try Self.load(name)
            let result = try Self.evaluate(replay)
            print("— \(replay.route) \(replay.tripId): \(replay.observations.count) fixes")
            print(Self.row("  display, estimate", result.display.estimate))
            print(Self.row("  display, reported fix", result.display.reported))
            print(Self.row("  display, server", result.display.server))
            display.append(result.display)
            nextFix.append(result.nextFix)
        }
        print("— All trips")
        print(Self.row("display, estimate", display.estimate))
        print(Self.row("display, reported fix", display.reported))
        print(Self.row("display, server", display.server))
        print(Self.row("next fix, estimate", nextFix.estimate))
        print(Self.row("next fix, reported fix", nextFix.reported))
        print(Self.row("next fix, server", nextFix.server))

        #expect(display.estimate.count > 500)
        #expect(Self.percentile(display.estimate, 0.5) < Self.percentile(display.reported, 0.5))
        #expect(Self.percentile(display.estimate, 0.9) < Self.percentile(display.reported, 0.9))
        #expect(Self.percentile(nextFix.estimate, 0.5) < Self.percentile(nextFix.reported, 0.5))
        #expect(Self.percentile(nextFix.estimate, 0.9) < Self.percentile(nextFix.reported, 0.9))
    }
}
