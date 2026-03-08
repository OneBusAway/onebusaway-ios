//
//  TransferContext.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Context about an in-progress trip transfer, used to customize the stop view
/// when navigating from a trip's stop list to a connecting stop.
public struct TransferContext: Equatable, Hashable {
    /// The time the rider is expected to arrive at the transfer stop.
    public let arrivalTime: Date

    /// The short name of the route the rider is currently on (e.g., "10").
    public let fromRouteShortName: String

    /// The headsign of the originating route (e.g., "Capitol Hill").
    public let fromTripHeadsign: String

    /// Combined route and headsign for display (e.g., "10 - Capitol Hill").
    /// Derived from `fromRouteShortName` and `fromTripHeadsign` so it can
    /// never contradict the component fields.
    public var fromRouteDisplay: String {
        [fromRouteShortName, fromTripHeadsign]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    public init(arrivalTime: Date, fromRouteShortName: String, fromTripHeadsign: String) {
        self.arrivalTime = arrivalTime
        self.fromRouteShortName = fromRouteShortName
        self.fromTripHeadsign = fromTripHeadsign
    }

    /// Convenience factory that extracts route info from an `ArrivalDeparture`.
    public static func from(arrivalDeparture: ArrivalDeparture, arrivalDate: Date) -> TransferContext {
        TransferContext(
            arrivalTime: arrivalDate,
            fromRouteShortName: arrivalDeparture.routeShortName,
            fromTripHeadsign: arrivalDeparture.tripHeadsign ?? ""
        )
    }

    /// Computes minutes from the transfer arrival time to the given departure date.
    /// Positive values mean the departure is after arrival; negative means before.
    public func minutesUntilDeparture(from departureDate: Date) -> Int {
        return Int(departureDate.timeIntervalSince(arrivalTime) / 60.0)
    }

    /// Returns the temporal state of a departure relative to this transfer's arrival time.
    public func temporalState(for departureDate: Date) -> TemporalState {
        let minutes = minutesUntilDeparture(from: departureDate)
        if minutes < 0 {
            return .past
        } else if minutes == 0 {
            return .present
        } else {
            return .future
        }
    }
}
