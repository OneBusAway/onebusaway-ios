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
//        case timeZone
//        case stopTimes
//        case previousTripID = "previousTripId"
//        case nextTripID = "nextTripId"
        case situationIDs = "situationIds"
    }

//    public init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//
//        frequency = try container.decodeIfPresent(Frequency.self, forKey: .frequency)
//        tripID = try container.decode(String.self, forKey: .tripID)
//        serviceDate = try container.decode(Date.self, forKey: .serviceDate)
//        status = try container.decodeIfPresent(TripStatus.self, forKey: .status)
//        situationIDs = try container.decode([String].self, forKey: .situationIDs)
//
//        let scheduleContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .schedule)
//        timeZone = try scheduleContainer.decode(String.self, forKey: .timeZone)
//        stopTimes = try scheduleContainer.decode([TripStopTime].self, forKey: .stopTimes)
//        previousTripID = try scheduleContainer.decodeIfPresent(String.self, forKey: .previousTripID)
//        nextTripID = try scheduleContainer.decodeIfPresent(String.self, forKey: .nextTripID)
//    }

//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encodeIfPresent(frequency, forKey: .frequency)
//        try container.encode(tripID, forKey: .tripID)
//        try container.encode(serviceDate, forKey: .serviceDate)
//        try container.encodeIfPresent(status, forKey: .status)
//        try container.encode(situationIDs, forKey: .situationIDs)
//
//        var scheduleContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .schedule)
//
//        try scheduleContainer.encode(timeZone, forKey: .timeZone)
//        try scheduleContainer.encode(stopTimes, forKey: .stopTimes)
//        try scheduleContainer.encodeIfPresent(previousTripID, forKey: .previousTripID)
//        try scheduleContainer.encodeIfPresent(nextTripID, forKey: .nextTripID)
//    }

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

        enum CodingKeys: String, CodingKey {
            case timeZone, stopTimes
            case previousTripID = "previousTripId"
            case nextTripID = "nextTripId"
        }
    }
}
