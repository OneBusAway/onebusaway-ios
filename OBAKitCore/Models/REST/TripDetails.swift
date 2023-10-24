//
//  TripDetails.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable

@Codable
public struct TripDetails: Identifiable, Hashable/* HasReferences*/ {
    public var id: String {
        return self.tripID
    }

    /// Captures information about a trip that uses frequency-based scheduling.
    /// Frequency-based scheduling is where a trip doesn’t have specifically
    /// scheduled stop times, but instead just a headway specifying the frequency
    /// of service (ex. service every 10 minutes).
    public let frequency: Frequency?

    /// The ID for the represented trip.
    @CodedAt("tripId")
    public let tripID: String
//    public private(set) var trip: Trip!

    public let serviceDate: Date

    /// Contains information about the current status of the transit vehicle serving this trip.
    public let status: TripStatus?

    /// The ID of the default time zone for this trip. e.g. `America/Los_Angeles`.
    @CodedAt("schedule", "timeZone")
    public let timeZone: String

    /// Specific details about which stops are visited during the course of the trip and at what times
    @CodedAt("schedule", "stopTimes")
    public let stopTimes: [TripStopTime]

    /// If this trip is part of a block and has an incoming trip from another route, this element will give the id of the incoming trip.
    @CodedAt("schedule", "previousTripId")
    public let previousTripID: String?

    /// If this trip is part of a block and has an incoming trip from another route, this element will provide the incoming trip.
//    public private(set) var previousTrip: Trip?

    /// If this trip is part of a block and has an outgoing trip to another route, this element will give the id of the outgoing trip.
    @CodedAt("schedule", "nextTripId")
    public let nextTripID: String?

    /// If this trip is part of a block and has an outgoing trip to another route, this will provide the outgoing trip.
//    public private(set) var nextTrip: Trip?

    /// Contains the IDs for any active `Situation` elements that currently apply to the trip.
    @CodedAt("situationIds")
    public let situationIDs: [String]

    /// Contains any active `ServiceAlert` elements that currently apply to the trip.
//    public private(set) var serviceAlerts = [ServiceAlert]()

//    public private(set) var regionIdentifier: Int?

    // MARK: - HasReferences
//
//    public func loadReferences(_ references: References, regionIdentifier: Int?) {
//        trip = references.tripWithID(tripID)!
//        previousTrip = references.tripWithID(previousTripID)
//        nextTrip = references.tripWithID(nextTripID)
//        serviceAlerts = references.serviceAlertsWithIDs(situationIDs)
//        stopTimes.loadReferences(references, regionIdentifier: regionIdentifier)
////        status?.loadReferences(references, regionIdentifier: regionIdentifier)
//        self.regionIdentifier = regionIdentifier
//    }
}
