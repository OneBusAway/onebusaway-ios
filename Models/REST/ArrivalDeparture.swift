//
//  ArrivalDeparture.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public enum ArrivalDepartureStatus: Int {
    case arriving, departing
}

public class ArrivalDeparture: NSObject, Decodable {

    /// true if this transit vehicle is one that riders could arrive on
    public let arrivalEnabled: Bool

    /// the index of this arrival's trip into the sequence of trips for the active block.
    /// Compare to `blockTripSequence` in a `TripStatus` element to determine where the
    /// `ArrivalDeparture` is on the block in comparison to the active block location.
    public let blockTripSequence: Int

    /// true if this transit vehicle is one that riders can depart on
    public let departureEnabled: Bool

    /// distance of the arriving transit vehicle from the stop, in meters
    public let distanceFromStop: Double

    /// Information about frequency based scheduling, if applicable to the trip
    public let frequency: Frequency?

    public let lastUpdated: Date

    /// The number of stops between the arriving transit vehicle and the current stop (doesn’t include the current stop)
    public let numberOfStopsAway: Int

    ///  true if we have real-time arrival info available for this trip
    public let predicted: Bool

    /// Predicted arrival time. `nil` if no real-time information is available.
    let predictedArrival: Date?

    /// Predicted departure time. `nil` if no real-time information is available.
    let predictedDeparture: Date?

    /// the route id for the arriving vehicle
    let routeID: String

    /// the route for the arriving vehicle
    public let route: Route

    /// the route long name that potentially overrides the route long name in the referenced `Route` element
    let _routeLongName: String?

    /// the route short name that potentially overrides the route short name in the referenced `Route` element
    let _routeShortName: String?

    /// The arrival date according to the schedule
    let scheduledArrival: Date

    /// The departure date according to the schedule
    let scheduledDeparture: Date

    /// Time of midnight for start of the service date for the trip
    public let serviceDate: Date

    /// Active service alert IDs for this trip.
    let situationIDs: [String]

    /// Active service alerts for this trip
    public let situations: [Situation]

    public let status: String

    /// The stop id of the stop the vehicle is arriving at
    let stopID: String

    /// The stop the vehicle is arriving at
    public let stop: Stop

    /// The index of the stop into the sequence of stops that make up the trip for this arrival
    public let stopSequence: Int

    /// The number of stops in this active trip
    public let totalStopsInTrip: Int?

    /// The trip headsign that potentially overrides the trip headsign in the referenced `Trip` element
    let _tripHeadsign: String?

    /// The trip id for the arriving vehicle
    let tripID: String

    /// The Trip for the arriving vehicle
    public let trip: Trip

    /// Trip-specific status for the arriving transit vehicle
    public let tripStatus: TripStatus?

    /// The ID of the arriving transit vehicle
    public let vehicleID: String

    private enum CodingKeys: String, CodingKey {
        case arrivalEnabled
        case blockTripSequence
        case departureEnabled
        case distanceFromStop
        case frequency
        case lastUpdated = "lastUpdateTime"
        case numberOfStopsAway
        case predicted
        case predictedArrival = "predictedArrivalTime"
        case predictedDeparture = "predictedDepartureTime"
        case routeID = "routeId"
        case routeLongName
        case routeShortName
        case scheduledArrival = "scheduledArrivalTime"
        case scheduledDeparture = "scheduledDepartureTime"
        case serviceDate
        case situationIDs = "situationIds"
        case status
        case stopID = "stopId"
        case stopSequence
        case totalStopsInTrip
        case tripHeadsign
        case tripID = "tripId"
        case tripStatus
        case vehicleID = "vehicleId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = decoder.userInfo[CodingUserInfoKey.references] as! References

        arrivalEnabled = try container.decode(Bool.self, forKey: .arrivalEnabled)
        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)
        departureEnabled = try container.decode(Bool.self, forKey: .departureEnabled)
        distanceFromStop = try container.decode(Double.self, forKey: .distanceFromStop)
        frequency = try? container.decode(Frequency.self, forKey: .frequency)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        numberOfStopsAway = try container.decode(Int.self, forKey: .numberOfStopsAway)
        predicted = try container.decode(Bool.self, forKey: .predicted)

        predictedArrival = ModelHelpers.nilifyEpochDate((try container.decode(Date.self, forKey: .predictedArrival)))

        predictedDeparture = ModelHelpers.nilifyEpochDate((try container.decode(Date.self, forKey: .predictedDeparture)))

        routeID = try container.decode(String.self, forKey: .routeID)
        route = references.routeWithID(routeID)!

        _routeLongName = ModelHelpers.nilifyBlankValue(try? container.decode(String.self, forKey: .routeLongName))
        _routeShortName = ModelHelpers.nilifyBlankValue(try? container.decode(String.self, forKey: .routeShortName))
        scheduledArrival = try container.decode(Date.self, forKey: .scheduledArrival)
        scheduledDeparture = try container.decode(Date.self, forKey: .scheduledDeparture)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        situations = references.situationsWithIDs(situationIDs)

        status = try container.decode(String.self, forKey: .status)

        stopID = try container.decode(String.self, forKey: .stopID)
        stop = references.stopWithID(stopID)!

        stopSequence = try container.decode(Int.self, forKey: .stopSequence)
        totalStopsInTrip = try? container.decode(Int.self, forKey: .totalStopsInTrip)
        _tripHeadsign = ModelHelpers.nilifyBlankValue(try? container.decode(String.self, forKey: .tripHeadsign))

        tripID = try container.decode(String.self, forKey: .tripID)
        trip = references.tripWithID(tripID)!

        tripStatus = try? container.decode(TripStatus.self, forKey: .tripStatus)
        vehicleID = try container.decode(String.self, forKey: .vehicleID)
    }
}

// MARK: - Helpers

extension ArrivalDeparture {

    // MARK: - Names

    /// Provides the best available trip headsign.
    public var tripHeadsign: String {
        return _tripHeadsign ?? trip.headsign
    }

    /// Provides the best available long name for this route.
    public var routeLongName: String? {
        return _routeLongName ?? route.longName
    }

    /// Provides the best available short name for this route.
    public var routeShortName: String {
        return _routeShortName ?? route.shortName
    }

    /// Provides the best available name for this route, which will either be the value of
    /// `routeLongName` or `routeShortName`, depending on whether or not `routeLongName` is nil.
    public var routeName: String {
        return routeLongName ?? routeShortName
    }

    /// A composite of the route name and headsign.
    public var routeAndHeadsign: String {
        return "\(routeName) - \(tripHeadsign)"
    }

    // MARK: - Transit Statuses and Times

    /// Whether this trip represents an arrival at or departure from this stop.
    ///
    /// This becomes relevant at the beginning of a trip, where a vehicle may have a significant delay
    /// between its arrival and departure due to a scheduled layover.
    public var arrivalDepartureStatus: ArrivalDepartureStatus {
        return stopSequence == 0 ? .departing : .arriving
    }

    /// A singluar value that can be displayed in the UI to represent the best date for this trip.
    public var arrivalDepartureDate: Date {
        switch arrivalDepartureStatus {
        case .arriving:
            return predictedArrival ?? scheduledArrival
        case .departing:
            return predictedDeparture ?? scheduledDeparture
        }
    }
}
