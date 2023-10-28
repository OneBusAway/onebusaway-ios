//
//  TripDetails.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public struct TripDetails: Identifiable, Codable, Hashable {
    /// Equivalent to `tripID`.
    public var id: String {
        return self.tripID
    }

    /// Captures information about a trip that uses frequency-based scheduling.
    /// Frequency-based scheduling is where a trip doesn’t have specifically
    /// scheduled stop times, but instead just a headway specifying the frequency
    /// of service (ex. service every 10 minutes).
    public let frequency: Frequency?

    /// The ID for the represented trip.
    public let tripID: String

    public let serviceDate: Date

    /// Contains information about the current status of the transit vehicle serving this trip.
    public let status: TripStatus?

    public let schedule: Schedule

    /// Contains the IDs for any active `Situation` elements that currently apply to the trip.
    public let situationIDs: [String]

    internal enum CodingKeys: String, CodingKey {
        case frequency
        case tripID = "tripId"
        case serviceDate
        case status
        case schedule
        case situationIDs = "situationIds"
    }

    // MARK: - Nested Types
    public struct Schedule: Codable, Hashable {
        /// The ID of the default time zone for this trip. e.g. `America/Los_Angeles`.
        public let timeZone: String

        /// Specific details about which stops are visited during the course of the trip and at what times
        public let stopTimes: [TripStopTime]

        /// If this trip is part of a block and has an incoming trip from another route, this element will give the id of the incoming trip.
        public let previousTripID: String?

        /// If this trip is part of a block and has an outgoing trip to another route, this element will give the id of the outgoing trip.
        public let nextTripID: String?

        internal enum CodingKeys: String, CodingKey {
            case timeZone, stopTimes
            case previousTripID = "previousTripId"
            case nextTripID = "nextTripId"
        }
    }
}
