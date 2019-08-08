//
//  ArrivalDeparture.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public typealias TripIdentifier = String

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
    let tripID: TripIdentifier

    /// The Trip for the arriving vehicle
    public let trip: Trip

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
        let references = decoder.references

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

        tripID = try container.decode(TripIdentifier.self, forKey: .tripID)
        trip = references.tripWithID(tripID)!

        tripStatus = try? container.decode(TripStatus.self, forKey: .tripStatus)
        vehicleID = ModelHelpers.nilifyBlankValue(try container.decode(String.self, forKey: .vehicleID))
    }

    // MARK: - Helpers/Names

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

    // MARK: - Equality and Hashing

    // TODO: Implement isEqual and hash on Route, Situation, Trip, and TripStatus,
    //  and add those members back in to the methods below.

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? ArrivalDeparture else { return false }
        return
            arrivalEnabled == rhs.arrivalEnabled &&
            blockTripSequence == rhs.blockTripSequence &&
            departureEnabled == rhs.departureEnabled &&
            distanceFromStop == rhs.distanceFromStop &&
            frequency == rhs.frequency &&
            lastUpdated == rhs.lastUpdated &&
            numberOfStopsAway == rhs.numberOfStopsAway &&
            predicted == rhs.predicted &&
            predictedArrival == rhs.predictedArrival &&
            predictedDeparture == rhs.predictedDeparture &&
            routeID == rhs.routeID &&
            _routeLongName == rhs._routeLongName &&
            _routeShortName == rhs._routeShortName &&
            scheduledArrival == rhs.scheduledArrival &&
            scheduledDeparture == rhs.scheduledDeparture &&
            serviceDate == rhs.serviceDate &&
            situationIDs == rhs.situationIDs &&
            status == rhs.status &&
            stopID == rhs.stopID &&
            stop == rhs.stop &&
            stopSequence == rhs.stopSequence &&
            totalStopsInTrip == rhs.totalStopsInTrip &&
            _tripHeadsign == rhs._tripHeadsign &&
            tripID == rhs.tripID &&
            vehicleID == rhs.vehicleID
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(arrivalEnabled);  hasher.combine(blockTripSequence)
        hasher.combine(departureEnabled); hasher.combine(distanceFromStop)
        hasher.combine(frequency); hasher.combine(lastUpdated)
        hasher.combine(numberOfStopsAway); hasher.combine(predicted)
        hasher.combine(predictedArrival); hasher.combine(predictedDeparture)
        hasher.combine(routeID)
        hasher.combine(_routeLongName); hasher.combine(_routeShortName)
        hasher.combine(scheduledArrival); hasher.combine(scheduledDeparture)
        hasher.combine(serviceDate); hasher.combine(situationIDs)
        hasher.combine(status)
        hasher.combine(stopID); hasher.combine(stop)
        hasher.combine(stopSequence); hasher.combine(totalStopsInTrip)
        hasher.combine(_tripHeadsign); hasher.combine(tripID)
        hasher.combine(vehicleID)
        return hasher.finalize()
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
