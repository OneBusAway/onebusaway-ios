//
//  TripStopTime.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public struct TripStopTime: Codable, Hashable, Comparable {
    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop.
    public let arrival: TimeInterval

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop
    public let departure: TimeInterval

    /// The stop id of the stop visited during the trip
    public let stopID: StopID

    public let distanceAlongTrip: Double

    public static func < (lhs: TripStopTime, rhs: TripStopTime) -> Bool {
        lhs.distanceAlongTrip < rhs.distanceAlongTrip
    }

    public func arrivalDate(relativeTo tripDetails: TripDetails) -> Date {
        tripDetails.serviceDate.addingTimeInterval(arrival)
    }

    public func departureDate(relativeTo tripDetails: TripDetails) -> Date {
        tripDetails.serviceDate.addingTimeInterval(departure)
    }

    internal enum CodingKeys: String, CodingKey {
        case arrival = "arrivalTime"
        case departure = "departureTime"
        case stopID = "stopId"
        case distanceAlongTrip
    }
}
