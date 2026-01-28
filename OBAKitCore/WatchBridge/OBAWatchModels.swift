//
//  OBAWatchModels.swift
//  OBAKitCore
//
//  Created by Prince Yadav on 01/01/26.
//

import Foundation
import CoreLocation

// MARK: - Core Identifiers

public typealias OBARouteID = String
public typealias OBAStopID = String
public typealias OBATripID = String

// MARK: - Core Models

/// A transit stop in a region.
public struct OBAArrivalsResult: Codable, Equatable, Sendable {
    public let arrivals: [OBAArrival]
    public let routes: [OBARoute]
    public let stopName: String?
    public let stopCode: String?
    public let stopDirection: String?

    public init(arrivals: [OBAArrival], routes: [OBARoute], stopName: String?, stopCode: String?, stopDirection: String?) {
        self.arrivals = arrivals
        self.routes = routes
        self.stopName = stopName
        self.stopCode = stopCode
        self.stopDirection = stopDirection
    }
}

public struct OBAStop: Codable, Equatable, Sendable, Identifiable {
    public let id: OBAStopID
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let code: String?
    public let direction: String?
    public let routeNames: String?
    public let locationType: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude = "lat"
        case longitude = "lon"
        case code
        case direction
        case routeNames
        case locationType
    }

    public init(
        id: OBAStopID,
        name: String,
        latitude: Double,
        longitude: Double,
        code: String? = nil,
        direction: String? = nil,
        routeNames: String? = nil,
        locationType: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.code = code
        self.direction = direction
        self.routeNames = routeNames
        self.locationType = locationType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(OBAStopID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)

        // "code" can be a string or a number in different deployments. Handle both.
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            self.code = stringCode
        } else if let intCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            self.code = String(intCode)
        } else {
            self.code = nil
        }
        self.direction = try? container.decodeIfPresent(String.self, forKey: .direction)
        self.routeNames = try? container.decodeIfPresent(String.self, forKey: .routeNames)
        self.locationType = try? container.decodeIfPresent(Int.self, forKey: .locationType)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(routeNames, forKey: .routeNames)
        try container.encodeIfPresent(locationType, forKey: .locationType)
    }
}

/// A lightweight representation of a specific vehicle in service.
public struct OBAVehicle: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let lastUpdateTime: Date?
    public let lastLocationUpdateTime: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let phase: String?
    public let status: String?
    public let tripID: OBATripID?

    public init(
        id: String,
        lastUpdateTime: Date? = nil,
        lastLocationUpdateTime: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        phase: String? = nil,
        status: String? = nil,
        tripID: OBATripID? = nil
    ) {
        self.id = id
        self.lastUpdateTime = lastUpdateTime
        self.lastLocationUpdateTime = lastLocationUpdateTime
        self.latitude = latitude
        self.longitude = longitude
        self.phase = phase
        self.status = status
        self.tripID = tripID
    }
}

/// A transit route (e.g. "10", "RapidRide B").
public struct OBARoute: Codable, Equatable, Sendable, Identifiable {
    public let id: OBARouteID
    public let shortName: String?
    public let longName: String?
    public let agencyName: String?

    public init(
        id: OBARouteID,
        shortName: String? = nil,
        longName: String? = nil,
        agencyName: String? = nil
    ) {
        self.id = id
        self.shortName = shortName
        self.longName = longName
        self.agencyName = agencyName
    }
}

/// A single direction of travel for a route, with its ordered list of stops.
public struct OBARouteDirection: Codable, Equatable, Sendable, Identifiable {
    /// Stable identifier for this direction (typically a directionId from the API).
    public let id: String
    /// Human-friendly name such as "Northbound" or "To Downtown".
    public let name: String?
    /// Ordered list of stops served in this direction.
    public let stops: [OBAStop]

    public init(id: String, name: String? = nil, stops: [OBAStop]) {
        self.id = id
        self.name = name
        self.stops = stops
    }
}

/// A specific trip on a route (e.g. a bus run).
public struct OBATrip: Codable, Equatable, Sendable, Identifiable {
    public let id: OBATripID
    public let routeID: OBARouteID
    public let headsign: String?

    public init(
        id: OBATripID,
        routeID: OBARouteID,
        headsign: String? = nil
    ) {
        self.id = id
        self.routeID = routeID
        self.headsign = headsign
    }
}

/// Extended details for a specific trip.
public struct OBATripDetails: Codable, Equatable, Sendable, Identifiable {
    public let id: OBATripID
    public let routeID: OBARouteID
    public let headsign: String?
    public let serviceID: String
    public let shapeID: String?
    public let directionID: String?
    public let blockID: String?

    public init(
        id: OBATripID,
        routeID: OBARouteID,
        headsign: String? = nil,
        serviceID: String,
        shapeID: String? = nil,
        directionID: String? = nil,
        blockID: String? = nil
    ) {
        self.id = id
        self.routeID = routeID
        self.headsign = headsign
        self.serviceID = serviceID
        self.shapeID = shapeID
        self.directionID = directionID
        self.blockID = blockID
    }
}

/// Detailed response from the `trip-details` API.
public struct OBATripExtendedDetails: Codable, Equatable, Sendable {
    public let tripId: String?
    public let serviceDate: Date?
    public let frequency: String?
    public let status: OBAVehicleTripStatus.Status?
    public let schedule: Schedule?

    public struct Schedule: Codable, Equatable, Sendable {
        public let timeZone: String?
        public let stopTimes: [StopTime]
        public let previousTripId: String?
        public let nextTripId: String?
        public let frequency: String?

        public init(timeZone: String?, stopTimes: [StopTime], previousTripId: String?, nextTripId: String?, frequency: String?) {
            self.timeZone = timeZone
            self.stopTimes = stopTimes
            self.previousTripId = previousTripId
            self.nextTripId = nextTripId
            self.frequency = frequency
        }
    }

    public struct StopTime: Codable, Equatable, Sendable {
        public let arrivalTime: Int?
        public let departureTime: Int?
        public let stopId: String?
        public let stopHeadsign: String?
        public let distanceAlongTrip: Double?
        public let historicalOccupancy: String?
        public let latitude: Double?
        public let longitude: Double?

        public init(arrivalTime: Int?, departureTime: Int?, stopId: String?, stopHeadsign: String?, distanceAlongTrip: Double?, historicalOccupancy: String?, latitude: Double?, longitude: Double?) {
            self.arrivalTime = arrivalTime
            self.departureTime = departureTime
            self.stopId = stopId
            self.stopHeadsign = stopHeadsign
            self.distanceAlongTrip = distanceAlongTrip
            self.historicalOccupancy = historicalOccupancy
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public init(tripId: String?, serviceDate: Date?, frequency: String?, status: OBAVehicleTripStatus.Status?, schedule: Schedule?) {
        self.tripId = tripId
        self.serviceDate = serviceDate
        self.frequency = frequency
        self.status = status
        self.schedule = schedule
    }
}

/// Extended status details for a vehicle on a trip.
public struct OBAVehicleTripStatus: Codable, Equatable, Sendable {
    public let tripID: OBATripID?
    public let serviceDate: Date?
    public let status: Status?
    public let schedule: OBATripExtendedDetails.Schedule?

    public struct Status: Codable, Equatable, Sendable {
        public let activeTripID: OBATripID?
        public let blockTripSequence: Int?
        public let serviceDate: Date?
        public let scheduleDeviation: Int?
        public let vehicleID: String?
        public let closestStop: OBAStopID?
        public let nextStop: OBAStopID?
        
        public let lastLocationUpdateTime: Date?
        public let lastUpdateTime: Date?
        
        public let position: Position?
        public let orientation: Double?
        
        public struct Position: Codable, Equatable, Sendable {
            public let lat: Double
            public let lon: Double

            public init(lat: Double, lon: Double) {
                self.lat = lat
                self.lon = lon
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case activeTripID = "activeTripId"
            case blockTripSequence
            case serviceDate
            case scheduleDeviation
            case vehicleID = "vehicleId"
            case closestStop
            case nextStop
            case lastLocationUpdateTime
            case lastUpdateTime
            case position
            case orientation
        }

        public init(activeTripID: OBATripID?, blockTripSequence: Int?, serviceDate: Date?, scheduleDeviation: Int?, vehicleID: String?, closestStop: OBAStopID?, nextStop: OBAStopID?, lastLocationUpdateTime: Date?, lastUpdateTime: Date?, position: Position?, orientation: Double?) {
            self.activeTripID = activeTripID
            self.blockTripSequence = blockTripSequence
            self.serviceDate = serviceDate
            self.scheduleDeviation = scheduleDeviation
            self.vehicleID = vehicleID
            self.closestStop = closestStop
            self.nextStop = nextStop
            self.lastLocationUpdateTime = lastLocationUpdateTime
            self.lastUpdateTime = lastUpdateTime
            self.position = position
            self.orientation = orientation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeTripID = try container.decodeIfPresent(OBATripID.self, forKey: .activeTripID)
            blockTripSequence = try container.decodeIfPresent(Int.self, forKey: .blockTripSequence)
            serviceDate = try container.decodeIfPresent(Date.self, forKey: .serviceDate)
            scheduleDeviation = try container.decodeIfPresent(Int.self, forKey: .scheduleDeviation)
            vehicleID = try container.decodeIfPresent(String.self, forKey: .vehicleID)
            closestStop = try container.decodeIfPresent(OBAStopID.self, forKey: .closestStop)
            nextStop = try container.decodeIfPresent(OBAStopID.self, forKey: .nextStop)
            lastLocationUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastLocationUpdateTime)
            lastUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastUpdateTime)
            position = try container.decodeIfPresent(Position.self, forKey: .position)
            orientation = try container.decodeIfPresent(Double.self, forKey: .orientation)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case tripID = "tripId"
        case serviceDate
        case status
        case schedule
    }

    public init(tripID: OBATripID?, serviceDate: Date?, status: Status?, schedule: OBATripExtendedDetails.Schedule?) {
        self.tripID = tripID
        self.serviceDate = serviceDate
        self.status = status
        self.schedule = schedule
    }
}

/// A simplified representation of a trip/vehicle at a location.
public struct OBATripForLocation: Codable, Equatable, Sendable, Identifiable {
    public let id: String // tripId
    public let vehicleID: String
    public let latitude: Double?
    public let longitude: Double?
    public let orientation: Double?
    public let routeID: String?
    public let routeShortName: String?
    public let tripHeadsign: String?
    public let lastUpdateTime: Date?

    public init(
        id: String,
        vehicleID: String,
        latitude: Double?,
        longitude: Double?,
        orientation: Double?,
        routeID: String?,
        routeShortName: String?,
        tripHeadsign: String?,
        lastUpdateTime: Date?
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.latitude = latitude
        self.longitude = longitude
        self.orientation = orientation
        self.routeID = routeID
        self.routeShortName = routeShortName
        self.tripHeadsign = tripHeadsign
        self.lastUpdateTime = lastUpdateTime
    }
}

/// A predicted or scheduled arrival/departure at a stop.
public struct OBAArrival: Codable, Equatable, Sendable, Identifiable {

    /// Stable identifier (typically stopID + tripID or server-provided ID).
    public let id: String

    public let stopID: OBAStopID
    public let routeID: OBARouteID
    public let tripID: OBATripID
    public let vehicleID: String?

    /// Human-facing label for the route (e.g. "10").
    public let routeShortName: String?
    /// Head-sign text (e.g. "Downtown").
    public let headsign: String?

    /// Arrival time relative to `referenceDate` in minutes.
    public let minutesFromNow: Int

    /// Whether this arrival is based on real-time prediction.
    public let isPredicted: Bool

    /// Coarse schedule status (early / on-time / delayed / unknown),
    /// mirroring ``ScheduleStatus`` from the iOS ArrivalDeparture model.
    public let scheduleStatus: OBAScheduleStatus

    public init(
        id: String,
        stopID: OBAStopID,
        routeID: OBARouteID,
        tripID: OBATripID,
        vehicleID: String? = nil,
        routeShortName: String? = nil,
        headsign: String? = nil,
        minutesFromNow: Int,
        isPredicted: Bool,
        scheduleStatus: OBAScheduleStatus = .unknown
    ) {
        self.id = id
        self.stopID = stopID
        self.routeID = routeID
        self.tripID = tripID
        self.vehicleID = vehicleID
        self.routeShortName = routeShortName
        self.headsign = headsign
        self.minutesFromNow = minutesFromNow
        self.isPredicted = isPredicted
        self.scheduleStatus = scheduleStatus
    }
}

/// Rough schedule adherence classification for an arrival.
public enum OBAScheduleStatus: String, Codable, Equatable, Sendable {
    case unknown
    case early
    case onTime
    case delayed
}

public extension OBAArrival {
    /// Human-friendly label for ``scheduleStatus`` suitable for UI.
    var scheduleStatusLabel: String? {
        switch scheduleStatus {
        case .unknown:
            return nil
        case .early:
            return "Early"
        case .onTime:
            return "On time"
        case .delayed:
            return "Delayed"
        }
    }
}

public struct OBANearbyStopsResult: Codable, Equatable, Sendable {
    public let stops: [OBAStop]
    public let stopIDToRouteNames: [OBAStopID: String]

    public init(stops: [OBAStop], stopIDToRouteNames: [OBAStopID: String]) {
        self.stops = stops
        self.stopIDToRouteNames = stopIDToRouteNames
    }
}

public struct OBAStopSchedule: Sendable, Codable, Equatable {
    public let stopID: OBAStopID
    public let date: Date
    public let stopTimes: [OBAStopScheduleStopTime]

    public init(stopID: OBAStopID, date: Date, stopTimes: [OBAStopScheduleStopTime]) {
        self.stopID = stopID
        self.date = date
        self.stopTimes = stopTimes
    }
}

public struct OBAStopScheduleStopTime: Sendable, Codable, Equatable {
    public let tripID: String
    public let arrivalTime: Date
    public let departureTime: Date
    public let stopHeadsign: String?

    public init(tripID: String, arrivalTime: Date, departureTime: Date, stopHeadsign: String?) {
        self.tripID = tripID
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.stopHeadsign = stopHeadsign
    }
}

public struct OBAAgencyCoverage: Codable, Equatable, Sendable, Identifiable {
    public var id: String { agencyID }
    public let agencyID: String
    public let centerLatitude: Double
    public let centerLongitude: Double

    public var agencyRegionBound: AgencyRegionBound {
        AgencyRegionBound(lat: centerLatitude, lon: centerLongitude, latSpan: 0.5, lonSpan: 0.5)
    }

    public init(agencyID: String, centerLatitude: Double, centerLongitude: Double) {
        self.agencyID = agencyID
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
    }
}

public struct AgencyRegionBound: Codable, Equatable, Sendable {
    public let lat: Double
    public let lon: Double
    public let latSpan: Double
    public let lonSpan: Double

    public init(lat: Double, lon: Double, latSpan: Double, lonSpan: Double) {
        self.lat = lat
        self.lon = lon
        self.latSpan = latSpan
        self.lonSpan = lonSpan
    }
}

public struct OBAStopProblemReport: Sendable {
    public let stopID: OBAStopID
    public let code: String
    public let comment: String?
    public let location: CLLocation?
    public init(stopID: OBAStopID, code: String, comment: String? = nil, location: CLLocation? = nil) {
        self.stopID = stopID
        self.code = code
        self.comment = comment
        self.location = location
    }
}

public struct OBATripProblemReport: Sendable {
    public let tripID: String
    public let serviceDate: Date
    public let vehicleID: String?
    public let stopID: OBAStopID?
    public let code: String
    public let comment: String?
    public let userOnVehicle: Bool
    public let location: CLLocation?
    public init(tripID: String, serviceDate: Date, vehicleID: String? = nil, stopID: OBAStopID? = nil, code: String, comment: String? = nil, userOnVehicle: Bool, location: CLLocation? = nil) {
        self.tripID = tripID
        self.serviceDate = serviceDate
        self.vehicleID = vehicleID
        self.stopID = stopID
        self.code = code
        self.comment = comment
        self.userOnVehicle = userOnVehicle
        self.location = location
    }
}
