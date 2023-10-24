//
//  TripStopTime.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

@Codable
public struct TripStopTime: Hashable, Comparable/* HasReferences*/ {
    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop.
    @CodedAt("arrivalTime")
    public let arrival: TimeInterval

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop
    @CodedAt("departureTime")
    public let departure: TimeInterval

    /// The stop id of the stop visited during the trip
    @CodedAt("stopId")
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

//    public private(set) var arrivalDate: Date!
//    public private(set) var departureDate: Date!


    /// The stop visited during the trip.
//    public private(set) var stop: Stop!

//    public private(set) var regionIdentifier: Int?

//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        stop = references.stopWithID(stopID)!
//        self.regionIdentifier = regionIdentifier
//    }
}
