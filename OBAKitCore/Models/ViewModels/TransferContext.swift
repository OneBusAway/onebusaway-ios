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

    /// The trip the rider is transferring from. Used on the redesigned stop
    /// page to highlight the matching departure row. Nil when constructed
    /// without a known trip (tests, legacy call sites).
    public let fromTripID: TripIdentifier?

    public init(
        arrivalTime: Date,
        fromRouteShortName: String,
        fromTripHeadsign: String,
        fromTripID: TripIdentifier? = nil
    ) {
        self.arrivalTime = arrivalTime
        self.fromRouteShortName = fromRouteShortName
        self.fromTripHeadsign = fromTripHeadsign
        self.fromTripID = fromTripID
    }

    /// Convenience factory that extracts route info from an `ArrivalDeparture`.
    public static func from(arrivalDeparture: ArrivalDeparture, arrivalDate: Date) -> TransferContext {
        TransferContext(
            arrivalTime: arrivalDate,
            fromRouteShortName: arrivalDeparture.routeShortName,
            fromTripHeadsign: arrivalDeparture.tripHeadsign ?? "",
            fromTripID: arrivalDeparture.tripID
        )
    }

    /// The context for stepping off the rider's trip at one of its stops, which
    /// the trip screens hand to the stop they open when a stop is tapped.
    ///
    /// - Parameters:
    ///   - stopID: The stop being opened.
    ///   - arrivalDate: When the trip reaches that stop. On a loop route that
    ///     calls at the stop twice, the time of the visit that was tapped.
    ///   - arrivalDeparture: The departure the rider is on.
    /// - Returns: `nil` without a departure (a trip opened from a vehicle has
    ///   no boarding stop), without a time, or for the stop the rider boards
    ///   at: transferring to the same stop is not meaningful.
    public static func toStop(_ stopID: StopID, arrivalDate: Date?, from arrivalDeparture: ArrivalDeparture?) -> TransferContext? {
        guard let arrivalDeparture, let arrivalDate, stopID != arrivalDeparture.stopID else { return nil }
        return .from(arrivalDeparture: arrivalDeparture, arrivalDate: arrivalDate)
    }
}
