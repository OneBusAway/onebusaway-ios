//
//  OBASharedCore.swift
//  OBASharedCore
//
//  Created by Prince Yadav on 01/01/26.
//
//  Platform-agnostic core for OneBusAway.
//  This module is intentionally pure Swift:
//  - Foundation only
//  - No UIKit / AppKit
//  - No SwiftUI
//  - No MapKit
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Core Identifiers

public typealias OBARouteID = String
public typealias OBAStopID = String
public typealias OBATripID = String

// MARK: - Core Models

/// A transit stop in a region.
public struct OBAStop: Identifiable, Codable, Equatable, Sendable {
    public let id: OBAStopID
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let code: String?
    public let direction: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude = "lat"
        case longitude = "lon"
        case code
        case direction
    }

    public init(
        id: OBAStopID,
        name: String,
        latitude: Double,
        longitude: Double,
        code: String? = nil,
        direction: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.code = code
        self.direction = direction
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(direction, forKey: .direction)
    }
}

/// Raw envelope for the `shape` API, which returns an encoded polyline
/// representing the vehicle path.
private struct OBARawShapeResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: Entry
    }

    struct Entry: Decodable, Sendable {
        let length: Int
        let levels: String
        let points: String
    }

    let data: Data
}

/// Minimal DTO for the `schedule-for-route` API used only to discover a
/// representative shapeId for a given route. This avoids pulling the full
/// schedule model into the shared core.
private struct OBARawScheduleForRouteResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: Entry
    }

    struct Entry: Decodable, Sendable {
        let trips: [Trip]
    }

    struct Trip: Decodable, Sendable {
        let id: OBATripID
        let routeId: OBARouteID
        let shapeId: String?
    }

    let data: Data

    func firstShapeID() -> String? {
        data.entry.trips.compactMap { $0.shapeId }.first
    }
}

/// A lightweight representation of a specific vehicle in service.
public struct OBAVehicle: Identifiable, Codable, Equatable, Sendable {
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

/// Thin DTO that mirrors the server's `ArrivalDeparture` JSON for just the
/// fields we care about in the shared core, and maps into ``OBAArrival``.
private struct OBARawArrival: Decodable, Sendable {
    let stopID: OBAStopID
    let routeID: OBARouteID
    let tripID: OBATripID

    let routeShortName: String?
    let tripHeadsign: String?
    let vehicleID: String?

    let predicted: Bool
    let predictedArrivalTime: Date?
    let predictedDepartureTime: Date?
    let scheduledArrivalTime: Date
    let scheduledDepartureTime: Date

    private enum CodingKeys: String, CodingKey {
        case stopID = "stopId"
        case routeID = "routeId"
        case tripID = "tripId"
        case routeShortName
        case tripHeadsign
        case vehicleID = "vehicleId"
        case predicted
        case predictedArrivalTime = "predictedArrivalTime"
        case predictedDepartureTime = "predictedDepartureTime"
        case scheduledArrivalTime = "scheduledArrivalTime"
        case scheduledDepartureTime = "scheduledDepartureTime"
    }

    /// Maps this raw object into an ``OBAArrival`` using ArrivalDeparture-like
    /// semantics for minutes-from-now and schedule status.
    func toDomainArrival(referenceDate now: Date = Date()) -> OBAArrival {
        // Choose the best time to display, roughly matching ArrivalDeparture.arrivalDepartureDate
        let bestDate = predictedArrivalTime
            ?? predictedDepartureTime
            ?? scheduledArrivalTime

        let minutesFromNow = Int(bestDate.timeIntervalSince(now) / 60.0)

        // Use scheduledDepartureTime as the reference scheduled time, similar to
        // how ArrivalDeparture compares against the scheduled departure.
        let deviationMinutes: Double = (bestDate.timeIntervalSince1970 - scheduledDepartureTime.timeIntervalSince1970) / 60.0

        let status: OBAScheduleStatus
        if !predicted {
            status = .unknown
        } else if deviationMinutes < -1.5 {
            status = .early
        } else if deviationMinutes < 1.5 {
            status = .onTime
        } else {
            status = .delayed
        }

        let id = "stop=\(stopID),trip=\(tripID),route=\(routeID)"

        return OBAArrival(
            id: id,
            stopID: stopID,
            routeID: routeID,
            tripID: tripID,
            vehicleID: vehicleID,
            routeShortName: routeShortName,
            headsign: tripHeadsign,
            minutesFromNow: minutesFromNow,
            isPredicted: predicted,
            scheduleStatus: status
        )
    }
}

/// A transit route (e.g. "10", "RapidRide B").
public struct OBARoute: Identifiable, Codable, Equatable, Sendable {
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
public struct OBARouteDirection: Identifiable, Codable, Equatable, Sendable {
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
public struct OBATrip: Identifiable, Codable, Equatable, Sendable {
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
public struct OBATripDetails: Identifiable, Codable, Equatable, Sendable {
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
    }

    public struct StopTime: Codable, Equatable, Sendable {
        public let arrivalTime: Int?
        public let departureTime: Int?
        public let stopId: String
        public let stopHeadsign: String?
        public let distanceAlongTrip: Double?
        public let historicalOccupancy: String?
    }
}

/// Extended status details for a vehicle on a trip.
public struct OBAVehicleTripStatus: Codable, Equatable, Sendable {
    public let tripID: OBATripID
    public let serviceDate: Date
    public let status: Status
    public let schedule: OBATripExtendedDetails.Schedule?

    public struct Status: Codable, Equatable, Sendable {
        public let activeTripID: OBATripID
        public let blockTripSequence: Int?
        public let serviceDate: Date
        public let scheduleDeviation: Int?
        public let vehicleID: String
        public let closestStop: OBAStopID?
        public let nextStop: OBAStopID?
        
        public let lastLocationUpdateTime: Date?
        public let lastUpdateTime: Date?
        
        public let position: Position?
        public let orientation: Double?
        
        public struct Position: Codable, Equatable, Sendable {
            public let lat: Double
            public let lon: Double
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
    }
    
    private enum CodingKeys: String, CodingKey {
        case tripID = "tripId"
        case serviceDate
        case status
        case schedule
    }
}

/// A simplified representation of a trip/vehicle at a location.
public struct OBATripForLocation: Identifiable, Codable, Equatable, Sendable {
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


/// Raw envelope for the `routes-for-stop` API.
private struct OBARawRoutesForStopResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [OBARoute]
    }

    let data: Data

    func toDomainRoutes() -> [OBARoute] {
        data.list
    }
}

/// A predicted or scheduled arrival/departure at a stop.
public struct OBAArrival: Identifiable, Codable, Equatable, Sendable {

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
public enum OBAScheduleStatus: String, Codable, Sendable {
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

// MARK: - Transport-layer DTOs

/// Generic list response shape that many REST endpoints follow.
/// Mirrors the structure of the OneBusAway `RESTAPIResponse` used in the iOS app,
/// but keeps only the pieces we need in the shared core.
private struct OBARawListResponse<Element: Decodable & Sendable>: Decodable, Sendable {
    private struct DataContainer: Decodable, Sendable {
        let list: Element?
        let entry: Element?
    }

    let list: Element

    private enum CodingKeys: String, CodingKey {
        case code, currentTime, text, version, data
    }

    init(from decoder: Decoder) throws {
        // Primary path: decode a standard OBA RESTAPIResponse-style envelope.
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.data) {
            let dataContainer = try container.decode(DataContainer.self, forKey: .data)

            if let entry = dataContainer.entry {
                self.list = entry
                return
            } else if let list = dataContainer.list {
                self.list = list
                return
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [CodingKeys.data],
                          debugDescription: "Expected either 'entry' or 'list' in data container.")
                )
            }
        }

        // Fallback: some deployments may return a bare list or single entry
        // without the usual envelope. In that case, decode Element directly
        // from the top level.
        self.list = try Element(from: decoder)
    }
}

/// Lightweight region payload used for watch connectivity.
/// Decodes only the fields needed to construct an API client configuration.
struct OBARawRegionPayload: Decodable, Sendable {
    let OBABaseURL: URL

    private enum CodingKeys: String, CodingKey {
        case OBABaseURL = "obaBaseUrl"
    }

    func toConfiguration() -> OBAURLSessionAPIClient.Configuration {
        OBAURLSessionAPIClient.Configuration(baseURL: OBABaseURL)
    }
}

/// Thin DTO that mirrors the server's `VehicleStatus` JSON for just the
/// fields we care about in the shared core, and maps into ``OBAVehicle``.
private struct OBARawVehicleStatus: Decodable, Sendable {
    let vehicleID: String
    let lastUpdateTime: Date?
    let lastLocationUpdateTime: Date?
    let latitude: Double?
    let longitude: Double?
    let phase: String?
    let status: String?
    let tripID: OBATripID?

    private enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicleId"
        case lastUpdateTime
        case lastLocationUpdateTime
        case location
        case phase
        case status
        case tripID = "tripId"
    }

    private enum LocationKeys: String, CodingKey {
        case lat
        case lon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        vehicleID = try container.decode(String.self, forKey: .vehicleID)
        lastUpdateTime = try? container.decode(Date.self, forKey: .lastUpdateTime)
        lastLocationUpdateTime = try? container.decode(Date.self, forKey: .lastLocationUpdateTime)
        phase = try? container.decode(String.self, forKey: .phase)
        status = try? container.decode(String.self, forKey: .status)
        tripID = try? container.decode(OBATripID.self, forKey: .tripID)

        if let locationContainer = try? container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location) {
            latitude = try? locationContainer.decode(Double.self, forKey: .lat)
            longitude = try? locationContainer.decode(Double.self, forKey: .lon)
        } else {
            latitude = nil
            longitude = nil
        }
    }

    func toDomainVehicle() -> OBAVehicle {
        OBAVehicle(
            id: vehicleID,
            lastUpdateTime: lastUpdateTime,
            lastLocationUpdateTime: lastLocationUpdateTime,
            latitude: latitude,
            longitude: longitude,
            phase: phase,
            status: status,
            tripID: tripID
        )
    }
}

/// Raw envelope for the `stops-for-location` API.
/// Mirrors the JSON structure shown in the OneBusAway REST docs and maps
/// into an array of ``OBAStop``.
private struct OBARawStopsForLocationResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [RawStop]?
        let references: References?
    }

    struct RawStop: Decodable, Sendable {
        let id: OBAStopID
        let name: String
        let lat: Double
        let lon: Double
        let code: String?
        let routeIds: [OBARouteID]?
        let direction: String?
    }

    struct References: Decodable, Sendable {
        struct RawRoute: Decodable, Sendable {
            let id: OBARouteID
            let shortName: String?
        }

        let stops: [RawStop]?
        let routes: [RawRoute]?
    }

    let data: Data

    func toDomainStops() -> [OBAStop] {
        (data.list ?? []).map { raw in
            OBAStop(
                id: raw.id,
                name: raw.name,
                latitude: raw.lat,
                longitude: raw.lon,
                code: raw.code,
                direction: raw.direction
            )
        }
    }

    /// Builds a lookup from stop ID to a comma-separated list of route
    /// short names serving that stop, if present in the references block.
    func stopIDToRouteNames() -> [OBAStopID: String] {
        guard let routes = data.references?.routes else { return [:] }

        let routeShortNameByID: [OBARouteID: String] = Dictionary(uniqueKeysWithValues: routes.compactMap { route in
            guard let short = route.shortName, !short.isEmpty else { return nil }
            return (route.id, short)
        })

        var result: [OBAStopID: String] = [:]
        for stop in (data.list ?? []) {
            guard let ids = stop.routeIds, !ids.isEmpty else { continue }
            let names = ids.compactMap { routeShortNameByID[$0] }
            guard !names.isEmpty else { continue }
            result[stop.id] = names.joined(separator: ", ")
        }

        return result
    }
}

/// Raw envelope for the `routes-for-location` API.
/// Maps into an array of ``OBARoute``.
private struct OBARawRoutesForLocationResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [RawRoute]?
        let references: References?
    }

    struct RawRoute: Decodable, Sendable {
        let id: OBARouteID
        let shortName: String?
        let longName: String?
        let description: String?
        let agencyId: String

        private enum CodingKeys: String, CodingKey {
            case id
            case shortName
            case longName
            case description
            case agencyId
        }
    }

    struct Agency: Decodable, Sendable {
        let id: String
        let name: String
    }

    struct References: Decodable, Sendable {
        let agencies: [Agency]?
    }

    let data: Data

    func toDomainRoutes() -> [OBARoute] {
        let agencyByID: [String: String] = Dictionary(uniqueKeysWithValues: (data.references?.agencies ?? []).map { agency in
            (agency.id, agency.name)
        })

        return (data.list ?? []).map { raw in
            OBARoute(
                id: raw.id,
                shortName: raw.shortName,
                longName: raw.longName?.isEmpty == false ? raw.longName : raw.description,
                agencyName: agencyByID[raw.agencyId]
            )
        }
    }
}

/// Raw envelope for the `trips-for-location` API.
private struct OBARawTripsForLocationResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [RawTrip]?
        let references: References?
    }

    struct RawTrip: Decodable, Sendable {
        let tripId: String
        let vehicleId: String
        let lastUpdateTime: Date?
        let location: Location?
        let tripStatus: TripStatus?
        
        struct Location: Decodable, Sendable {
            let lat: Double
            let lon: Double
        }
        
        struct TripStatus: Decodable, Sendable {
            let activeTripId: String
            let orientation: Double?
            let position: Location?
            let lastKnownLocation: Location?
        }
    }
    
    struct References: Decodable, Sendable {
        let routes: [RawRoute]?
        let trips: [RawTripRef]?
    }
    
    struct RawRoute: Decodable, Sendable {
        let id: String
        let shortName: String?
    }
    
    struct RawTripRef: Decodable, Sendable {
        let id: String
        let routeId: String
        let tripHeadsign: String?
    }
    
    let data: Data
    
    func toDomain() -> [OBATripForLocation] {
        guard let list = data.list else { return [] }
        
        // Build lookups
        var routeShortNameByID: [String: String] = [:]
        if let routes = data.references?.routes {
            for route in routes {
                routeShortNameByID[route.id] = route.shortName
            }
        }
        
        var tripRefByID: [String: RawTripRef] = [:]
        if let trips = data.references?.trips {
            for trip in trips {
                tripRefByID[trip.id] = trip
            }
        }
        
        return list.map { item in
            // Determine effective trip ID (item.tripId might be empty, check status)
            let effectiveTripID = !item.tripId.isEmpty ? item.tripId : (item.tripStatus?.activeTripId ?? "")
            
            // Determine location
            let lat = item.location?.lat
                ?? item.tripStatus?.position?.lat
                ?? item.tripStatus?.lastKnownLocation?.lat
            let lon = item.location?.lon
                ?? item.tripStatus?.position?.lon
                ?? item.tripStatus?.lastKnownLocation?.lon
                
            let orientation = item.tripStatus?.orientation
            
            // Resolve route and headsign
            var routeID: String?
            var routeShortName: String?
            var tripHeadsign: String?
            
            if !effectiveTripID.isEmpty, let ref = tripRefByID[effectiveTripID] {
                routeID = ref.routeId
                tripHeadsign = ref.tripHeadsign
                routeShortName = routeShortNameByID[ref.routeId]
            }
            
            return OBATripForLocation(
                id: effectiveTripID,
                vehicleID: item.vehicleId,
                latitude: lat,
                longitude: lon,
                orientation: orientation,
                routeID: routeID,
                routeShortName: routeShortName,
                tripHeadsign: tripHeadsign,
                lastUpdateTime: item.lastUpdateTime
            )
        }
    }
}

/// Thin DTOs for the `stops-for-route` API that provide route directions
/// and their associated stops.
private struct OBARawStopsForRouteResponse: Decodable, Sendable {
    let data: OBARawStopsForRoute
}

private struct OBARawStopsForRoute: Decodable, Sendable {
    let references: References?
    let entry: Entry

    struct References: Decodable, Sendable {
        let stops: [RawStop]
    }

    struct RawStop: Decodable, Sendable {
        let id: OBAStopID
        let name: String
        let lat: Double
        let lon: Double
        let code: String?
    }

    struct Entry: Decodable, Sendable {
        let stopGroupings: [StopGrouping]
    }

    struct StopGrouping: Decodable, Sendable {
        let ordered: [OrderedStops]
    }

    struct OrderedStops: Decodable, Sendable {
        let id: String
        let name: Name?
        let stopIDs: [OBAStopID]

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case stopIDs = "stopIds"
        }
    }

    struct Name: Decodable, Sendable {
        let name: String?
    }

    func toDomainDirections() -> [OBARouteDirection] {
        // Index stops by ID for quick lookup
        let stopByID: [OBAStopID: OBAStop] = Dictionary(uniqueKeysWithValues: (references?.stops ?? []).map { raw in
            let stop = OBAStop(
                id: raw.id,
                name: raw.name,
                latitude: raw.lat,
                longitude: raw.lon,
                code: raw.code
            )
            return (raw.id, stop)
        })

        // The first stopGrouping typically contains directions-by-stop
        guard let grouping = entry.stopGroupings.first else { return [] }

        return grouping.ordered.map { ordered in
            let stops = ordered.stopIDs.compactMap { stopByID[$0] }
            return OBARouteDirection(
                id: ordered.id,
                name: ordered.name?.name,
                stops: stops
            )
        }.filter { !$0.stops.isEmpty }
    }
}

/// Thin DTO for the `trip` API.
private struct OBARawTripDetails: Decodable, Sendable {
    let id: OBATripID
    let routeID: OBARouteID
    let tripHeadsign: String?
    let serviceID: String
    let shapeID: String?
    let directionID: String?
    let blockID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case routeID = "routeId"
        case tripHeadsign
        case serviceID = "serviceId"
        case shapeID = "shapeId"
        case directionID = "directionId"
        case blockID = "blockId"
    }

    func toDomain() -> OBATripDetails {
        OBATripDetails(
            id: id,
            routeID: routeID,
            headsign: tripHeadsign,
            serviceID: serviceID,
            shapeID: shapeID,
            directionID: directionID,
            blockID: blockID
        )
    }
}

/// Raw envelope for the `trip-details` API.
private struct OBARawTripDetailsResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: OBATripExtendedDetails
        let references: References?
    }

    struct References: Decodable, Sendable {
        let stops: [RawStop]?
    }

    struct RawStop: Decodable, Sendable {
        let id: String
        let name: String
    }

    let data: Data
}

// MARK: - API Client Protocol

/// A minimal, platform-agnostic API surface suitable for watchOS and iOS.
///
/// Implementations are responsible for talking to the real OneBusAway server
/// or a local cache, but they must remain Foundation-only.
public struct OBANearbyStopsResult: Sendable {
    public let stops: [OBAStop]
    public let stopIDToRouteNames: [OBAStopID: String]

    public init(stops: [OBAStop], stopIDToRouteNames: [OBAStopID: String]) {
        self.stops = stops
        self.stopIDToRouteNames = stopIDToRouteNames
    }
}

public protocol OBAAPIClient: Sendable {
    func fetchArrivalDepartureAtStop(
        stopID: OBAStopID,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int
    ) async throws -> OBAArrival

    func fetchStop(id: OBAStopID) async throws -> OBAStop

    func fetchScheduleForStop(
        stopID: OBAStopID,
        date: Date?
    ) async throws -> OBAStopSchedule

    func fetchAgenciesWithCoverage() async throws -> [OBAAgencyCoverage]

    func submitStopProblem(_ report: OBAStopProblemReport) async throws

    func submitTripProblem(_ report: OBATripProblemReport) async throws

    /// Fetches stops near a given coordinate.
    /// - Parameters:
    ///   - latitude: Latitude in degrees.
    ///   - longitude: Longitude in degrees.
    ///   - radius: Search radius in meters.
    func fetchNearbyStops(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> OBANearbyStopsResult

    /// Searches for stops whose name or code matches the given query, biased
    /// around a coordinate. This mirrors the iOS app's getStops(circularRegion:query:)
    /// behavior but is kept minimal for shared use.
    /// - Parameters:
    ///   - query: Free-form search string (stop name, code, etc.).
    ///   - latitude: Center latitude in degrees.
    ///   - longitude: Center longitude in degrees.
    ///   - radius: Search radius in meters.
    func searchStops(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> OBANearbyStopsResult

    /// Fetches upcoming arrivals for a stop.
    /// - Parameter stopID: The stop identifier.
    func fetchArrivals(for stopID: OBAStopID) async throws -> [OBAArrival]

    /// Fetches active trips (vehicles) near a location.
    /// - Parameters:
    ///   - latitude: Center latitude.
    ///   - longitude: Center longitude.
    ///   - latSpan: Latitude span (height of the bounding box).
    ///   - lonSpan: Longitude span (width of the bounding box).
    func fetchTripsForLocation(
        latitude: Double,
        longitude: Double,
        latSpan: Double,
        lonSpan: Double
    ) async throws -> [OBATripForLocation]

    /// Searches for routes whose name or shortName matches the given query,
    /// biased around a coordinate. This mirrors the iOS
    /// `routes-for-location` behavior in a minimal way.
    /// - Parameters:
    ///   - query: Free-form search string (route number, name, etc.).
    ///   - latitude: Center latitude in degrees.
    ///   - longitude: Center longitude in degrees.
    ///   - radius: Search radius in meters.
    func searchRoutes(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [OBARoute]

    /// Fetches routes that serve a particular stop.
    /// - Parameter stopID: The stop identifier.
    func fetchRoutesForStop(stopID: OBAStopID) async throws -> [OBARoute]

    /// Retrieves the set of stops serving a particular route, grouped by
    /// direction of travel. This is a lightweight projection of the
    /// `/stops-for-route` API used by the iOS app.
    /// - Parameter routeID: The route identifier.
    func fetchStopsForRoute(routeID: OBARouteID) async throws -> [OBARouteDirection]

    /// Attempts to resolve a representative shape identifier for a route
    /// using the `schedule-for-route` API. Returns nil if no shape can be
    /// determined.
    func fetchShapeIDForRoute(routeID: OBARouteID) async throws -> String?

    /// Fetches the encoded polyline points for a shape identifier.
    /// Callers are responsible for decoding the polyline into coordinates.
    func fetchShape(shapeID: String) async throws -> String

    /// Fetches basic information about a single vehicle by ID.
    /// - Parameter vehicleID: The vehicle identifier string.
    func fetchVehicle(vehicleID: String) async throws -> OBAVehicle

    /// Fetches details for a specific trip.
    /// - Parameter tripID: The trip identifier.
    func fetchTrip(tripID: OBATripID) async throws -> OBATripDetails

    /// Fetches extended trip details for a specific transit vehicle.
    /// - Parameter vehicleID: The vehicle identifier.
    func fetchTripForVehicle(vehicleID: String) async throws -> OBAVehicleTripStatus

    /// Fetches extended details for a specific trip, including schedule and status.
    /// - Parameter tripID: The trip identifier.
    func fetchTripDetails(tripID: OBATripID) async throws -> OBATripExtendedDetails

    /// Retrieves the current system time from the OneBusAway server.
    func fetchCurrentTime() async throws -> Date
}

// MARK: - URLSession-based API Client

/// A simple, URLSession-backed implementation of ``OBAAPIClient``.
///
/// This intentionally avoids any knowledge of UIKit/SwiftUI and can be used
/// from both iOS and watchOS. It expects the server to expose JSON payloads
/// compatible with the shared models above.
public final class OBAURLSessionAPIClient: OBAAPIClient {

    public struct Configuration: Sendable {
        public let baseURL: URL
        public let apiKey: String?

        /// Time window for arrivals, mirroring the iOS client's
        /// `minutesBefore` / `minutesAfter` parameters.
        public let minutesBeforeArrivals: UInt
        public let minutesAfterArrivals: UInt

        public init(
            baseURL: URL,
            apiKey: String? = nil,
            minutesBeforeArrivals: UInt = 5,
            minutesAfterArrivals: UInt = 35
        ) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.minutesBeforeArrivals = minutesBeforeArrivals
            self.minutesAfterArrivals = minutesAfterArrivals
        }
    }

    private let configuration: Configuration
    private let urlSession: URLSession

    public init(
        configuration: Configuration,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    // MARK: OBAAPIClient
    public func fetchArrivalDepartureAtStop(
        stopID: OBAStopID,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int
    ) async throws -> OBAArrival {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/arrival-and-departure-for-stop/\(stopID).json"
        var params: [URLQueryItem] = [
            URLQueryItem(name: "tripId", value: tripID),
            URLQueryItem(name: "serviceDate", value: String(Int64(serviceDate.timeIntervalSince1970 * 1000)))
        ] + apiKeyQueryItem
        if let vehicleID {
            params.append(URLQueryItem(name: "vehicleId", value: vehicleID))
        }
        if stopSequence > 0 {
            params.append(URLQueryItem(name: "stopSequence", value: String(stopSequence)))
        }
        components?.queryItems = params

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawListResponse<OBARawArrival> = try await get(url: url)
        return response.list.toDomainArrival()
    }

    public func fetchStop(id: OBAStopID) async throws -> OBAStop {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/stop/\(id).json"
        components?.queryItems = apiKeyQueryItem
        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawStopResponse = try await get(url: url)
        return response.toDomainStop()
    }

    public func fetchScheduleForStop(
        stopID: OBAStopID,
        date: Date?
    ) async throws -> OBAStopSchedule {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/schedule-for-stop/\(stopID).json"
        var items = apiKeyQueryItem
        if let date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "date", value: formatter.string(from: date)))
        }
        components?.queryItems = items
        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawScheduleForStopResponse = try await get(url: url)
        return response.toDomainSchedule()
    }

    public func fetchAgenciesWithCoverage() async throws -> [OBAAgencyCoverage] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/agencies-with-coverage.json"
        components?.queryItems = apiKeyQueryItem
        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawAgenciesWithCoverageResponse = try await get(url: url)
        return response.toDomainAgencies()
    }

    public func submitStopProblem(_ report: OBAStopProblemReport) async throws {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/report-problem-with-stop/\(report.stopID).json"
        var items = apiKeyQueryItem + [
            URLQueryItem(name: "code", value: report.code),
        ]
        if let comment = report.comment, !comment.isEmpty {
            items.append(URLQueryItem(name: "userComment", value: comment))
        }
        if let loc = report.location {
            items.append(contentsOf: [
                URLQueryItem(name: "userLat", value: String(loc.coordinate.latitude)),
                URLQueryItem(name: "userLon", value: String(loc.coordinate.longitude)),
                URLQueryItem(name: "userLocationAccuracy", value: String(loc.horizontalAccuracy))
            ])
        }
        components?.queryItems = items
        let url = try components?.url ?? { throw URLError(.badURL) }()
        let (_, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func submitTripProblem(_ report: OBATripProblemReport) async throws {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/report-problem-with-trip.json"
        var items = apiKeyQueryItem + [
            URLQueryItem(name: "tripId", value: report.tripID),
            URLQueryItem(name: "serviceDate", value: String(Int64(report.serviceDate.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "code", value: report.code),
            URLQueryItem(name: "userOnVehicle", value: report.userOnVehicle ? "true" : "false")
        ]
        if let vehicleID = report.vehicleID {
            items.append(URLQueryItem(name: "vehicleId", value: vehicleID))
        }
        if let stopID = report.stopID {
            items.append(URLQueryItem(name: "stopId", value: stopID))
        }
        if let comment = report.comment, !comment.isEmpty {
            items.append(URLQueryItem(name: "userComment", value: comment))
        }
        if let loc = report.location {
            items.append(contentsOf: [
                URLQueryItem(name: "userLat", value: String(loc.coordinate.latitude)),
                URLQueryItem(name: "userLon", value: String(loc.coordinate.longitude)),
                URLQueryItem(name: "userLocationAccuracy", value: String(loc.horizontalAccuracy))
            ])
        }
        components?.queryItems = items
        let url = try components?.url ?? { throw URLError(.badURL) }()
        let (_, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func fetchNearbyStops(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> OBANearbyStopsResult {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/stops-for-location.json"
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius))
        ] + apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawStopsForLocationResponse = try await get(url: url)
        return OBANearbyStopsResult(
            stops: response.toDomainStops(),
            stopIDToRouteNames: response.stopIDToRouteNames()
        )
    }

    public func searchStops(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> OBANearbyStopsResult {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/stops-for-location.json"
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "query", value: query)
        ] + apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawStopsForLocationResponse = try await get(url: url)
        return OBANearbyStopsResult(
            stops: response.toDomainStops(),
            stopIDToRouteNames: response.stopIDToRouteNames()
        )
    }

    public func fetchArrivals(for stopID: OBAStopID) async throws -> [OBAArrival] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/arrivals-and-departures-for-stop/\(stopID).json"
        components?.queryItems = apiKeyQueryItem + [
            URLQueryItem(name: "minutesBefore", value: String(configuration.minutesBeforeArrivals)),
            URLQueryItem(name: "minutesAfter", value: String(configuration.minutesAfterArrivals))
        ]

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawListResponse<[OBARawArrival]> = try await get(url: url)
        let now = Date()
        return response.list.map { $0.toDomainArrival(referenceDate: now) }
    }

    public func fetchTripsForLocation(
        latitude: Double,
        longitude: Double,
        latSpan: Double,
        lonSpan: Double
    ) async throws -> [OBATripForLocation] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/trips-for-location.json"
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "latSpan", value: String(latSpan)),
            URLQueryItem(name: "lonSpan", value: String(lonSpan))
        ] + apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawTripsForLocationResponse = try await get(url: url)
        return response.toDomain()
    }

    public func fetchRoutesForStop(stopID: OBAStopID) async throws -> [OBARoute] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/routes-for-stop/\(stopID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawRoutesForStopResponse = try await get(url: url)
        return response.toDomainRoutes()
    }

    public func searchRoutes(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [OBARoute] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/routes-for-location.json"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius))
        ]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        components?.queryItems = items + apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawRoutesForLocationResponse = try await get(url: url)
        return response.toDomainRoutes()
    }

    public func fetchStopsForRoute(routeID: OBARouteID) async throws -> [OBARouteDirection] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/stops-for-route/\(routeID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawStopsForRouteResponse = try await get(url: url)
        return response.data.toDomainDirections()
    }

    public func fetchShapeIDForRoute(routeID: OBARouteID) async throws -> String? {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/schedule-for-route/\(routeID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawScheduleForRouteResponse = try await get(url: url)
        return response.firstShapeID()
    }

    public func fetchShape(shapeID: String) async throws -> String {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/shape/\(shapeID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawShapeResponse = try await get(url: url)
        return response.data.entry.points
    }

    public func fetchVehicle(vehicleID: String) async throws -> OBAVehicle {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/vehicle/\(vehicleID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawListResponse<OBARawVehicleStatus> = try await get(url: url)
        return response.list.toDomainVehicle()
    }

    public func fetchTrip(tripID: OBATripID) async throws -> OBATripDetails {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/trip/\(tripID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawListResponse<OBARawTripDetails> = try await get(url: url)
        return response.list.toDomain()
    }

    public func fetchTripForVehicle(vehicleID: String) async throws -> OBAVehicleTripStatus {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/trip-for-vehicle/\(vehicleID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        let response: OBARawListResponse<OBAVehicleTripStatus> = try await get(url: url)
        return response.list
    }

    public func fetchTripDetails(tripID: OBATripID) async throws -> OBATripExtendedDetails {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/trip-details/\(tripID).json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        
        let response: OBARawTripDetailsResponse = try await get(url: url)
        var details = response.data.entry
        
        // Enhance stop times with names from references if needed
        if let stops = response.data.references?.stops, let schedule = details.schedule {
            let stopNameByID = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0.name) })
            
            let enhancedStopTimes = schedule.stopTimes.map { stopTime -> OBATripExtendedDetails.StopTime in
                if stopTime.stopHeadsign != nil { return stopTime }
                let name = stopNameByID[stopTime.stopId]
                
                return OBATripExtendedDetails.StopTime(
                    arrivalTime: stopTime.arrivalTime,
                    departureTime: stopTime.departureTime,
                    stopId: stopTime.stopId,
                    stopHeadsign: name,
                    distanceAlongTrip: stopTime.distanceAlongTrip,
                    historicalOccupancy: stopTime.historicalOccupancy
                )
            }
            
            let enhancedSchedule = OBATripExtendedDetails.Schedule(
                timeZone: schedule.timeZone,
                stopTimes: enhancedStopTimes,
                previousTripId: schedule.previousTripId,
                nextTripId: schedule.nextTripId,
                frequency: schedule.frequency
            )
            
            details = OBATripExtendedDetails(
                tripId: details.tripId,
                serviceDate: details.serviceDate,
                frequency: details.frequency,
                status: details.status,
                schedule: enhancedSchedule
            )
        }
        
        return details
    }

    public func fetchCurrentTime() async throws -> Date {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/api/where/current-time.json"
        components?.queryItems = apiKeyQueryItem

        let url = try components?.url ?? { throw URLError(.badURL) }()
        // We only care about the top-level "currentTime" field in the JSON response,
        // but our generic `get` decodes a specific type.
        // Let's make a tiny local struct to capture the time.
        struct CurrentTimeResponse: Decodable {
            let currentTime: Date
        }
        
        let (data, response) = try await urlSession.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
             throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let result = try decoder.decode(CurrentTimeResponse.self, from: data)
        return result.currentTime
    }

    // MARK: - Helpers

    private var apiKeyQueryItem: [URLQueryItem] {
        if let key = configuration.apiKey, !key.isEmpty {
            return [URLQueryItem(name: "key", value: key)]
        }
        return []
    }

    private func get<Response: Decodable & Sendable>(url: URL) async throws -> Response {
        let (data, response) = try await urlSession.data(from: url)
        
        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                // Success - proceed with decoding
                break
            case 404:
                throw URLError(.badServerResponse) // Will be caught and handled as "not found"
            case 400...499:
                throw URLError(.badServerResponse) // Client error
            case 500...599:
                throw URLError(.badServerResponse) // Server error
            default:
                throw URLError(.badServerResponse)
            }
        }
        
        // Handle servers that return a literal `null` body for missing resources
        if data.count <= 6 {
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if s == "null" || s == "" {
                throw URLError(.badServerResponse)
            }
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Response.self, from: data)
    }
}

// MARK: - New domain types for watch-required APIs

public struct OBAStopSchedule: Sendable, Codable {
    public let stopID: OBAStopID
    public let date: Date
    public let stopTimes: [OBAStopScheduleStopTime]
}

public struct OBAStopScheduleStopTime: Sendable, Codable {
    public let tripID: String
    public let arrivalTime: Date
    public let departureTime: Date
    public let stopHeadsign: String?
}

public struct OBAAgencyCoverage: Sendable, Codable {
    public let agencyID: String
    public let centerLatitude: Double
    public let centerLongitude: Double

    public var agencyRegionBound: AgencyRegionBound {
        AgencyRegionBound(lat: centerLatitude, lon: centerLongitude, latSpan: 0.5, lonSpan: 0.5)
    }
}

public struct AgencyRegionBound: Codable {
    public let lat: Double
    public let lon: Double
    public let latSpan: Double
    public let lonSpan: Double

    public var serviceRect: MKMapRect {
        let centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let latitudinalMeters = latSpan * 111320.0 // Approximation for degrees latitude to meters
        let longitudinalMeters = lonSpan * 111320.0 * cos(lat * .pi / 180.0) // Approximation for degrees longitude to meters

        let region = MKCoordinateRegion(center: centerCoordinate, latitudinalMeters: latitudinalMeters, longitudinalMeters: longitudinalMeters)

        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2, longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2, longitude: region.center.longitude + region.span.longitudeDelta / 2))

        return MKMapRect(x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y), width: abs(topLeft.x - bottomRight.x), height: abs(topLeft.y - bottomRight.y))
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

// MARK: - New raw decoders

private struct OBARawStopResponse: Decodable, Sendable {
    private struct Data: Decodable, Sendable {
        let entry: OBARawStopsForLocationResponse.RawStop
    }
    private let data: Data
    func toDomainStop() -> OBAStop {
        OBAStop(
            id: data.entry.id,
            name: data.entry.name,
            latitude: data.entry.lat,
            longitude: data.entry.lon,
            code: data.entry.code,
            direction: data.entry.direction
        )
    }
}

private struct OBARawScheduleForStopResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: Entry
    }
    struct Entry: Decodable, Sendable {
        let stopId: String
        let date: Double
        let stopRouteSchedules: [StopRouteSchedule]
    }
    struct StopRouteSchedule: Decodable, Sendable {
        let stopRouteDirectionSchedules: [StopRouteDirectionSchedule]
    }
    struct StopRouteDirectionSchedule: Decodable, Sendable {
        let scheduleStopTimes: [StopScheduleStopTime]
    }
    struct StopScheduleStopTime: Decodable, Sendable {
        let tripId: String
        let arrivalTime: Int64
        let departureTime: Int64
        let stopHeadsign: String?
    }
    private let data: Data
    func toDomainSchedule() -> OBAStopSchedule {
        let times: [OBAStopScheduleStopTime] = data.entry.stopRouteSchedules
            .flatMap { $0.stopRouteDirectionSchedules }
            .flatMap { $0.scheduleStopTimes }
            .map {
                OBAStopScheduleStopTime(
                    tripID: $0.tripId,
                    arrivalTime: Date(timeIntervalSince1970: Double($0.arrivalTime) / 1000.0),
                    departureTime: Date(timeIntervalSince1970: Double($0.departureTime) / 1000.0),
                    stopHeadsign: ($0.stopHeadsign?.isEmpty == true) ? nil : $0.stopHeadsign
                )
            }
        return OBAStopSchedule(
            stopID: data.entry.stopId,
            date: Date(timeIntervalSince1970: data.entry.date / 1000.0),
            stopTimes: times
        )
    }
}

private struct OBARawAgenciesWithCoverageResponse: Decodable, Sendable {
    struct DataContainer: Decodable, Sendable {
        let list: [AgencyRaw]
    }
    struct AgencyRaw: Decodable, Sendable {
        let agencyId: String
        let lat: Double
        let lon: Double
        let latSpan: Double?
        let lonSpan: Double?
    }
    private let data: DataContainer
    func toDomainAgencies() -> [OBAAgencyCoverage] {
        data.list.map {
            OBAAgencyCoverage(
                agencyID: $0.agencyId,
                centerLatitude: $0.lat,
                centerLongitude: $0.lon
            )
        }
    }
}

