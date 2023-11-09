//
//  ArrivalDeparture.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public typealias TripIdentifier = String

public struct ArrivalDeparture: Identifiable, Codable, Hashable {

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
    public let routeID: RouteID

    /// the route for the arriving vehicle
    public var route: Route!

    /// the route long name that potentially overrides the route long name in the referenced `Route` element
    public let routeLongName: String?

    /// the route short name that potentially overrides the route short name in the referenced `Route` element
    public let routeShortName: String?

    /// The arrival date according to the schedule
    let scheduledArrival: Date

    /// The departure date according to the schedule
    let scheduledDeparture: Date

    /// Time of midnight for start of the service date for the trip
    public let serviceDate: Date

    /// Active service alert IDs for this trip.
    public let situationIDs: [String]

    public let status: String

    /// The stop id of the stop the vehicle is arriving at
    public let stopID: StopID

    /// The index of the stop into the sequence of stops that make up the trip for this arrival
    public let stopSequence: Int

    /// The number of stops in this active trip
    public let totalStopsInTrip: Int?

    /// The trip headsign that potentially overrides the trip headsign in the referenced `Trip` element
    public let tripHeadsign: String?

    /// The trip id for the arriving vehicle
    public let tripID: TripIdentifier

    /// Trip-specific status for the arriving transit vehicle
    public let tripStatus: TripStatus?

    /// The ID of the arriving transit vehicle
    public let vehicleID: String?

    private enum CodingKeys: String, CodingKey {
        case arrivalEnabled
        case blockTripSequence
        case departureEnabled
        case distanceFromStop
        case frequency
        case occupancyStatus
        case historicalOccupancyStatus = "historicalOccupancy"
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        arrivalEnabled = try container.decode(Bool.self, forKey: .arrivalEnabled)
        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)
        departureEnabled = try container.decode(Bool.self, forKey: .departureEnabled)
        distanceFromStop = try container.decode(Double.self, forKey: .distanceFromStop)
        frequency = try? container.decodeIfPresent(Frequency.self, forKey: .frequency)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        numberOfStopsAway = try container.decode(Int.self, forKey: .numberOfStopsAway)
        predicted = try container.decode(Bool.self, forKey: .predicted)

        if let predictedArrivalDate = try container.decodeIfPresent(Date.self, forKey: .predictedArrival) {
            predictedArrival = ModelHelpers.nilifyDate(predictedArrivalDate, earlierThan: Date(timeIntervalSinceReferenceDate: 1.0))
        } else {
            predictedArrival = nil
        }

        if let predictedDepartureDate = try container.decodeIfPresent(Date.self, forKey: .predictedDeparture) {
            predictedDeparture = ModelHelpers.nilifyDate(predictedDepartureDate, earlierThan: Date(timeIntervalSinceReferenceDate: 1.0))
        } else {
            predictedDeparture = nil
        }

        routeID = try container.decode(RouteID.self, forKey: .routeID)

        routeLongName = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeLongName))
        routeShortName = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeShortName))
        scheduledArrival = try container.decode(Date.self, forKey: .scheduledArrival)
        scheduledDeparture = try container.decode(Date.self, forKey: .scheduledDeparture)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)

        situationIDs = try container.decode([String].self, forKey: .situationIDs)

        status = try container.decode(String.self, forKey: .status)

        stopID = try container.decode(String.self, forKey: .stopID)

        stopSequence = try container.decode(Int.self, forKey: .stopSequence)
        totalStopsInTrip = try? container.decodeIfPresent(Int.self, forKey: .totalStopsInTrip)
        tripHeadsign = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .tripHeadsign))

        tripID = try container.decode(TripIdentifier.self, forKey: .tripID)

        tripStatus = try? container.decodeIfPresent(TripStatus.self, forKey: .tripStatus)
        vehicleID = String.nilifyBlankValue(try container.decode(String.self, forKey: .vehicleID))

        occupancyStatus = try container.decodeIfPresent(OccupancyStatus.self, forKey: .occupancyStatus)
        historicalOccupancyStatus = try container.decodeIfPresent(OccupancyStatus.self, forKey: .historicalOccupancyStatus)
    }

    // MARK: - Helpers/Names

    /// Provides an ID for this arrival departure consisting of its Stop, Trip, and Route IDs.
    public var id: String {
        return "stop=\(stopID),trip=\(tripID),route=\(routeID),status=\(arrivalDepartureStatus)"
    }

    /// A composite of the route name and headsign.
    public var routeAndHeadsign: String {
        fatalError("PR-686 error: \(#function) unimplemented")
//        [String.nilifyBlankValue(routeName), String.nilifyBlankValue(tripHeadsign)]
//            .compactMap { $0 }
//            .joined(separator: " - ")
    }

    // MARK: - Helpers/Statuses+Times

    /// Whether this trip represents an arrival at or departure from this stop.
    ///
    /// This becomes relevant at the beginning of a trip, where a vehicle may have a significant delay
    /// between its arrival and departure due to a scheduled layover.
    public var arrivalDepartureStatus: ArrivalDepartureStatus {
        return stopSequence == 0 ? .departing : .arriving
    }

    /// True if this is the last stop on a given trip, false if it is not, and nil if the result can't be determined.
    public var isLastStopOnTrip: Bool? {
        guard let totalStopsInTrip = totalStopsInTrip else { return nil }

        return stopSequence == totalStopsInTrip - 1
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

    /// A singular value that can be displayed in the UI to represent the best scheduled date for this trip.
    public var scheduledDate: Date {
        switch arrivalDepartureStatus {
        case .arriving:
            return scheduledArrival
        case .departing:
            return scheduledDeparture
        }
    }

    /// Number of minutes until/after `arrivalDepartureDate`.
    public var arrivalDepartureMinutes: Int {
        return Int(arrivalDepartureDate.timeIntervalSinceNow / 60.0)
    }

    /// Whether `arrivalDepartureDate` occurred in the past, is occurring now, or is occurring in the future.
    public var temporalState: TemporalState {
        let minutes = arrivalDepartureMinutes
        if minutes < 0 {
            // Arrived/Departed abs(minutes) min ago
            return .past
        }
        else if minutes == 0 {
            // Arriving/Departing now
            return .present
        }
        else {
            // Arrives/Departs in (minutes) min
            return .future
        }
    }

    /// This is the number of minutes that the predicted arrival/departure time deviates
    /// from the official, scheduled arrival/departure time for this vehicle on this trip.
    ///
    /// - Note: This value is an approximation, and is calculated by rounding and then
    ///         truncating the raw deviation.
    public var deviationFromScheduleInMinutes: Int {
        return Int(round(rawDeviationFromScheduleInMinutes))
    }

    /// A more precise (but maybe not as useful?) calculation of the deviation of this trip from schedule.
    private var rawDeviationFromScheduleInMinutes: Double {
        return (arrivalDepartureDate.timeIntervalSinceNow - scheduledDeparture.timeIntervalSinceNow) / 60.0
    }

    /// Is this trip early, on time, delayed, or of an unknown status?
    public var scheduleStatus: ScheduleStatus {
        guard predicted else {
            return .unknown
        }

        let minutesDiff = rawDeviationFromScheduleInMinutes
        if minutesDiff < -1.5 {
            return .early
        }
        else if minutesDiff < 1.5 {
            return .onTime
        }
        else {
            return .delayed
        }
    }

    // MARK: - Occupancy Status

    /// For transit systems that support it, this value represents the current occupancy
    /// of the vehicle represented by this ArrivalDeparture object.
    ///
    /// For more information, see https://developers.google.com/transit/gtfs-realtime/reference#enum-occupancystatus
    public let occupancyStatus: OccupancyStatus?

    /// For transit systems that support it, this value represents the historical occupancy
    /// of the vehicle represented by this ArrivalDeparture object.
    public let historicalOccupancyStatus: OccupancyStatus?

    public enum OccupancyStatus: String, Codable {
        case unknown = ""
        case empty = "EMPTY"
        case manySeatsAvailable = "MANY_SEATS_AVAILABLE"
        case fewSeatsAvailable = "FEW_SEATS_AVAILABLE"
        case standingRoomOnly = "STANDING_ROOM_ONLY"
        case crushedStandingRoomOnly = "CRUSHED_STANDING_ROOM_ONLY"
        case full = "FULL"
        case notAcceptingPassengers = "NOT_ACCEPTING_PASSENGERS"
    }

}

public enum ArrivalDepartureStatus: Int {
    case arriving, departing
}

public enum ScheduleStatus: Int {
    case unknown, early, onTime, delayed
}

public enum TemporalState: Int {
    case past, present, future
}

// MARK: - [ArrivalDeparture] Extensions

public extension Sequence where Element == ArrivalDeparture {
    /// Filters out all `ArrivalDeparture` objects from the receiver that should be hidden according to `preferences`.
    /// - Parameter preferences: The `StopPreferences` object that will be used to hide `ArrivalDeparture`s.
    func filter(preferences: StopPreferences) -> [ArrivalDeparture] {
        filter { !preferences.isRouteIDHidden($0.routeID) }
    }

    /// Filters out `Route`s that are marked as hidden by `preferences`, and then groups the remaining `ArrivalDeparture`s by `Route`.
    /// - Parameter preferences: The `StopPreferences` object that will be used to hide `ArrivalDeparture`s.
    /// - Parameter filter: Whether the groups should also be filtered (i.e. have `Route`s hidden).
    func group(preferences: StopPreferences, filter: Bool) -> [GroupedArrivalDeparture] {
        let hiddenRoutes = Set(preferences.hiddenRoutes)

        var groups = [Route: [ArrivalDeparture]]()

        for arrDep in self {
            if filter && hiddenRoutes.contains(arrDep.routeID) {
                continue
            }

            var list = groups[arrDep.route, default: [ArrivalDeparture]()]
            list.append(arrDep)
            groups[arrDep.route] = list
        }

        return groups.map { (k, v) -> GroupedArrivalDeparture in
            GroupedArrivalDeparture(route: k, arrivalDepartures: v)
        }
    }
}
