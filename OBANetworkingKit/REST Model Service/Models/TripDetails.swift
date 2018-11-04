//
//  TripDetails.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class TripDetails: NSObject, Decodable {

    /// Captures information about a trip that uses frequency-based scheduling.
    /// Frequency-based scheduling is where a trip doesn’t have specifically
    /// scheduled stop times, but instead just a headway specifying the frequency
    /// of service (ex. service every 10 minutes).
    public let frequency: Frequency?

    /// The ID for the represented trip.
    public let tripID: String
    public let trip: Trip

    public let serviceDate: Date

    /// Contains information about the current status of the transit vehicle serving this trip.
    public let status: TripStatus?

    /// The ID of the default time zone for this trip. e.g. `America/Los_Angeles`.
    public let timeZone: String

    /// Specific details about which stops are visited during the course of the trip and at what times
    public let stopTimes: [TripStopTime]

    /// If this trip is part of a block and has an incoming trip from another route, this element will give the id of the incoming trip.
    let previousTripID: String?

    /// If this trip is part of a block and has an incoming trip from another route, this element will provide the incoming trip.
    public let previousTrip: Trip?

    /// If this trip is part of a block and has an outgoing trip to another route, this element will give the id of the outgoing trip.
    let nextTripID: String?

    /// If this trip is part of a block and has an outgoing trip to another route, this will provide the outgoing trip.
    public let nextTrip: Trip?

    /// Contains the IDs for any active `Situation` elements that currently apply to the trip.
    let situationIDs: [String]

    /// Contains any active `Situation` elements that currently apply to the trip.
    public let situations: [Situation]

    private enum CodingKeys: String, CodingKey {
        case frequency
        case tripID = "tripId"
        case serviceDate
        case status
        case schedule
        case timeZone
        case stopTimes
        case previousTripID = "previousTripId"
        case nextTripID = "nextTripId"
        case situationIDs = "situationIds"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.userInfo[CodingUserInfoKey.references] as! References

        frequency = try? container.decode(Frequency.self, forKey: .frequency)

        tripID = try container.decode(String.self, forKey: .tripID)
        trip = references.tripWithID(tripID)!

        serviceDate = try container.decode(Date.self, forKey: .serviceDate)
        status = try? container.decode(TripStatus.self, forKey: .status)

        let schedule = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .schedule)
        timeZone = try schedule.decode(String.self, forKey: .timeZone)
        stopTimes = try schedule.decode([TripStopTime].self, forKey: .stopTimes)

        previousTripID = try? schedule.decode(String.self, forKey: .previousTripID)
        previousTrip = references.tripWithID(previousTripID)

        nextTripID = try? schedule.decode(String.self, forKey: .nextTripID)
        nextTrip = references.tripWithID(nextTripID)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        situations = references.situationsWithIDs(situationIDs)
    }
}

public class TripStopTime: NSObject, Decodable {

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop.
    let arrival: TimeInterval

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop
    let departure: TimeInterval

    /// The stop id of the stop visited during the trip
    let stopID: String

    private enum CodingKeys: String, CodingKey {
        case arrival = "arrivalTime"
        case departure = "departureTime"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        arrival = try container.decode(TimeInterval.self, forKey: .arrival)
        departure = try container.decode(TimeInterval.self, forKey: .departure)
        stopID = try container.decode(String.self, forKey: .stopID)
    }
}
