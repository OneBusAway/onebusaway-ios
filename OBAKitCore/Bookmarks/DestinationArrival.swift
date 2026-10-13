//
//  DestinationArrival.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// When a trip that departs a bookmark's origin stop is expected at the
/// bookmark's destination stop.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1080
public struct DestinationArrival: Equatable, Sendable {
    /// The best available arrival time at the destination: the scheduled time
    /// shifted by the trip's current deviation when real-time data exists.
    public let arrivalDate: Date

    /// The timetabled arrival time at the destination.
    public let scheduledArrivalDate: Date

    /// `true` when `arrivalDate` reflects real-time data rather than the schedule alone.
    public let isRealTime: Bool

    public init(arrivalDate: Date, scheduledArrivalDate: Date, isRealTime: Bool) {
        self.arrivalDate = arrivalDate
        self.scheduledArrivalDate = scheduledArrivalDate
        self.isRealTime = isRealTime
    }

    /// Estimates when `origin`'s trip reaches `destinationStopID`.
    ///
    /// The trip's deviation from schedule at the origin is carried forward to the
    /// destination. OBA servers propagate a vehicle's delay down the rest of its
    /// trip the same way, and it keeps the arrival consistent with the departure
    /// the card shows next to it.
    ///
    /// The origin is located by `origin.stopSequence` (its index in the trip's
    /// stop list), falling back to the first visit to its stop ID if the two
    /// disagree. The destination must come *after* the origin, so a loop trip
    /// that visits the destination before the origin does not report a time
    /// that has already passed.
    ///
    /// - Parameters:
    ///   - origin: The departure from the bookmark's origin stop.
    ///   - stopTimes: The scheduled stop times for `origin`'s trip, in trip order.
    ///   - destinationStopID: The stop the rider gets off at.
    /// - Returns: The arrival, or `nil` when this trip does not reach the destination after the origin.
    public static func estimate(
        origin: ArrivalDeparture,
        stopTimes: [TripStopTime],
        destinationStopID: StopID
    ) -> DestinationArrival? {
        guard let originIndex = originIndex(of: origin, in: stopTimes) else { return nil }

        let remaining = stopTimes[stopTimes.index(after: originIndex)...]
        guard
            let destination = remaining.first(where: { $0.stopID == destinationStopID }),
            let scheduledArrival = destination.arrivalDate
        else {
            return nil
        }

        let deviation: TimeInterval = origin.predicted
            ? origin.arrivalDepartureDate.timeIntervalSince(origin.scheduledDate)
            : 0

        return DestinationArrival(
            arrivalDate: scheduledArrival.addingTimeInterval(deviation),
            scheduledArrivalDate: scheduledArrival,
            isRealTime: origin.predicted
        )
    }

    private static func originIndex(of origin: ArrivalDeparture, in stopTimes: [TripStopTime]) -> Int? {
        let sequence = origin.stopSequence
        if stopTimes.indices.contains(sequence), stopTimes[sequence].stopID == origin.stopID {
            return sequence
        }
        return stopTimes.firstIndex { $0.stopID == origin.stopID }
    }
}

/// What is known about a single departure's arrival at a bookmark's destination.
public enum DestinationArrivalLookup: Equatable, Sendable {
    /// The trip's schedule has not been loaded yet.
    case pending

    /// The trip's schedule could not be loaded (a 404, a server without trip
    /// details, a flaky network). Distinct from `pending` so the card stops
    /// saying the arrival is loading; the loader retries on the next refresh.
    case unavailable

    /// The trip does not stop at the destination after the origin, e.g. a short-turn trip.
    case notServed

    /// The trip reaches the destination.
    case arrives(DestinationArrival)
}

/// Identifies one run of a trip, the unit at which schedules are cached.
struct TripScheduleKey: Hashable, Sendable {
    let tripID: TripIdentifier
    let serviceDate: Date

    init(arrivalDeparture: ArrivalDeparture) {
        self.tripID = arrivalDeparture.tripID
        self.serviceDate = arrivalDeparture.serviceDate
    }
}
