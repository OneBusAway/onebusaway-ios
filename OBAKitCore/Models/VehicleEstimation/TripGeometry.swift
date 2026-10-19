//
//  TripGeometry.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A trip's shape with its stops placed on it: everything static the estimator
/// needs. Built once per trip.
public struct TripGeometry: Sendable {

    /// A stop time as the server reports it.
    public struct StopTime: Sendable {
        /// Meters along the trip, in the server's measure of the shape.
        public let distanceAlongTrip: Double?
        public let arrival: Date
        public let departure: Date

        public init(distanceAlongTrip: Double?, arrival: Date, departure: Date) {
            self.distanceAlongTrip = distanceAlongTrip
            self.arrival = arrival
            self.departure = departure
        }
    }

    /// A stop on the client shape.
    public struct Stop: Sendable {
        public let distanceAlongShape: Double
        public let arrival: Date
        public let departure: Date
    }

    public let shape: ShapeLine
    /// Empty when the schedule can't be placed on the shape (see `init`).
    public let stops: [Stop]

    public var hasSchedule: Bool { !stops.isEmpty }

    /// Scheduled time against distance, strictly increasing in both: stops that
    /// share a scheduled time (GTFS times are often whole minutes) collapse into
    /// the first of them, so no span has zero duration.
    private let knots: [(s: Double, t: TimeInterval)]

    /// - Parameters:
    ///   - serverTripLength: `TripStatus.totalDistanceAlongTrip`. Both servers measure
    ///     the shape themselves, a little differently from the polyline the client
    ///     decodes, so stop distances are rescaled by `shape.length / serverTripLength`.
    ///     `nil` or non-positive falls back to the last stop's distance.
    ///
    /// The schedule is dropped, leaving only the shape, when any stop lacks a distance,
    /// when distances go backward, or when every distance is zero (maglev's shapeless trip).
    public init(shape: ShapeLine, stopTimes: [StopTime], serverTripLength: Double?) {
        self.shape = shape

        let distances = stopTimes.compactMap(\.distanceAlongTrip)
        let usable = distances.count == stopTimes.count
            && distances.count >= 2
            && zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 }
            && (distances.last ?? 0) > 0
        guard usable else {
            stops = []
            knots = []
            return
        }

        let serverLength = serverTripLength.flatMap { $0 > 0 ? $0 : nil } ?? distances[distances.count - 1]
        let scale = shape.length / serverLength
        let stops = zip(stopTimes, distances).map { stopTime, distance in
            Stop(
                distanceAlongShape: min(max(distance * scale, 0), shape.length),
                arrival: stopTime.arrival,
                departure: stopTime.departure
            )
        }
        self.stops = stops

        let origin = stops[0].departure
        var knots: [(s: Double, t: TimeInterval)] = [(stops[0].distanceAlongShape, 0)]
        for stop in stops.dropFirst() {
            let t = stop.arrival.timeIntervalSince(origin)
            guard t > knots[knots.count - 1].t, stop.distanceAlongShape > knots[knots.count - 1].s else { continue }
            knots.append((stop.distanceAlongShape, t))
        }
        self.knots = knots.count >= 2 ? knots : []
    }

    /// Seconds after the first stop's departure at which the schedule has the
    /// vehicle `s` meters along. Linear between stops, flat before the first and
    /// after the last. `nil` without a schedule.
    public func scheduledTime(at s: Double) -> TimeInterval? {
        guard let index = knotIndex(containing: s) else { return nil }
        let a = knots[index], b = knots[index + 1]
        let clamped = min(max(s, a.s), b.s)
        return a.t + (clamped - a.s) / (b.s - a.s) * (b.t - a.t)
    }

    /// The schedule's speed `s` meters along, in m/s. `nil` without a schedule.
    public func scheduledSpeed(at s: Double) -> Double? {
        guard let index = knotIndex(containing: s) else { return nil }
        let a = knots[index], b = knots[index + 1]
        return (b.s - a.s) / (b.t - a.t)
    }

    /// Where the current scheduled span ends, so a walk along it can change speed
    /// there. `nil` past the last span or without a schedule.
    func scheduledSpanEnd(after s: Double) -> Double? {
        guard let index = knotIndex(containing: s) else { return nil }
        return knots[index + 1].s > s ? knots[index + 1].s : nil
    }

    private func knotIndex(containing s: Double) -> Int? {
        guard knots.count >= 2 else { return nil }
        var low = 0, high = knots.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if knots[mid].s <= s { low = mid } else { high = mid }
        }
        return low
    }
}
