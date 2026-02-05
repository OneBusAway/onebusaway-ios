//
//  OBAWatchDTOs.swift
//  OBAKitCore
//
//  Created by Prince Yadav on 01/01/26.
//

import Foundation
import CoreLocation

// MARK: - Transport-layer DTOs

/// Raw envelope for the `shape` API, which returns an encoded polyline
/// representing the vehicle path.
struct OBARawShapeResponse: Decodable, Sendable {
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
struct OBARawScheduleForRouteResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: Entry?
        let trips: [Trip]?
    }

    struct Entry: Decodable, Sendable {
        let trips: [Trip]?
    }

    struct Trip: Decodable, Sendable {
        let id: OBATripID?
        let routeId: OBARouteID?
        let shapeId: String?
    }

    let data: Data

    func firstShapeID() -> String? {
        (data.entry?.trips ?? data.trips ?? []).compactMap { $0.shapeId }.first
    }
}

/// Thin DTO that mirrors the server's `ArrivalDeparture` JSON for just the
/// fields we care about in the shared core, and maps into ``OBAArrival``.
struct OBARawArrival: Decodable, Sendable {
    let stopID: OBAStopID?
    let routeID: OBARouteID?
    let tripID: OBATripID?

    let routeShortName: String?
    let tripHeadsign: String?
    let vehicleID: String?

    let predicted: Bool?
    let predictedArrivalTime: Date?
    let predictedDepartureTime: Date?
    let scheduledArrivalTime: Date?
    let scheduledDepartureTime: Date?

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
            ?? scheduledDepartureTime
            ?? now

        let minutesFromNow = Int(bestDate.timeIntervalSince(now) / 60.0)

        // Use scheduledDepartureTime as the reference scheduled time, similar to
        // how ArrivalDeparture compares against the scheduled departure.
        let refSchedTime = scheduledDepartureTime ?? scheduledArrivalTime ?? now
        let deviationMinutes: Double = (bestDate.timeIntervalSince1970 - refSchedTime.timeIntervalSince1970) / 60.0

        let status: OBAScheduleStatus
        if !(predicted ?? false) {
            status = .unknown
        } else if deviationMinutes < -1.5 {
            status = .early
        } else if deviationMinutes < 1.5 {
            status = .onTime
        } else {
            status = .delayed
        }

        if self.stopID == nil || self.tripID == nil || self.routeID == nil {
            Logger.error("OBARawArrival missing critical IDs: stopID=\(String(describing: self.stopID)), tripID=\(String(describing: self.tripID)), routeID=\(String(describing: self.routeID))")
        }

        let stopID = self.stopID ?? ""
        let tripID = self.tripID ?? ""
        let routeID = self.routeID ?? ""
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
            isPredicted: predicted ?? false,
            scheduleStatus: status
        )
    }
}

/// Raw envelope for the `routes-for-stop` API.
struct OBARawRoutesForStopResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [OBARawRoutesForLocationResponse.RawRoute]?
        let routes: [OBARawRoutesForLocationResponse.RawRoute]?
    }

    let data: Data

    func toDomainRoutes() -> [OBARoute] {
        (data.list ?? data.routes ?? []).map { raw in
            OBARoute(
                id: raw.id,
                shortName: raw.shortName,
                longName: raw.longName?.isEmpty == false ? raw.longName : raw.description
            )
        }
    }
}

/// Generic list response shape that many REST endpoints follow.
/// Mirrors the structure of the OneBusAway `RESTAPIResponse` used in the iOS app,
/// but keeps only the pieces we need in the shared core.
struct OBARawListResponse<Element: Decodable & Sendable>: Decodable, Sendable {
    private struct DataContainer: Decodable, Sendable {
        let list: Element?
        let entry: Element?
        let stops: Element?
        let routes: Element?
        let trips: Element?
        let arrivalsAndDepartures: Element?
        let stop: OBARawStopResponse.StopEntry?
        let references: OBARawStopResponse.References?
    }

    let list: Element
    let stop: OBARawStopResponse.StopEntry?
    let references: OBARawStopResponse.References?

    private enum CodingKeys: String, CodingKey {
        case code, currentTime, text, version, data
    }

    init(from decoder: Decoder) throws {
        // Primary path: decode a standard OBA RESTAPIResponse-style envelope.
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.data) {
            let dataContainer = try container.decode(DataContainer.self, forKey: .data)
            self.stop = dataContainer.stop
            self.references = dataContainer.references

            if let entry = dataContainer.entry {
                self.list = entry
                return
            } else if let list = dataContainer.list {
                self.list = list
                return
            } else if let stops = dataContainer.stops {
                self.list = stops
                return
            } else if let routes = dataContainer.routes {
                self.list = routes
                return
            } else if let trips = dataContainer.trips {
                self.list = trips
                return
            } else if let arrivalsAndDepartures = dataContainer.arrivalsAndDepartures {
                self.list = arrivalsAndDepartures
                return
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [CodingKeys.data],
                          debugDescription: "Expected a known data key (entry, list, stops, routes, trips, arrivalsAndDepartures) in data container.")
                )
            }
        }

        // Fallback: some deployments may return a bare list or single entry
        // without the usual envelope. In that case, decode Element directly
        // from the top level.
        self.list = try Element(from: decoder)
        self.stop = nil
        self.references = nil
    }
}

/// Thin DTO that mirrors the server's `VehicleStatus` JSON for just the
/// fields we care about in the shared core, and maps into ``OBAVehicle``.
struct OBARawVehicleStatus: Decodable, Sendable {
    let vehicleID: String?
    let lastUpdateTime: Date?
    let lastLocationUpdateTime: Date?
    let latitude: Double?
    let longitude: Double?
    let phase: String?
    let status: String?
    let tripID: OBATripID?
    let routeShortName: String?
    let tripHeadsign: String?

    private enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicleId"
        case lastUpdateTime
        case lastLocationUpdateTime
        case location
        case phase
        case status
        case tripID = "tripId"
        case routeShortName
        case tripHeadsign
    }

    private enum LocationKeys: String, CodingKey {
        case lat
        case lon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vehicleID = try container.decodeIfPresent(String.self, forKey: .vehicleID)
        self.lastUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastUpdateTime)
        self.lastLocationUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastLocationUpdateTime)
        self.phase = try container.decodeIfPresent(String.self, forKey: .phase)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.tripID = try container.decodeIfPresent(OBATripID.self, forKey: .tripID)
        self.routeShortName = try container.decodeIfPresent(String.self, forKey: .routeShortName)
        self.tripHeadsign = try container.decodeIfPresent(String.self, forKey: .tripHeadsign)

        if let locationContainer = try? container.nestedContainer(keyedBy: LocationKeys.self, forKey: .location) {
            self.latitude = try locationContainer.decodeIfPresent(Double.self, forKey: .lat)
            self.longitude = try locationContainer.decodeIfPresent(Double.self, forKey: .lon)
        } else {
            self.latitude = nil
            self.longitude = nil
        }
    }

    func toDomainVehicle() -> OBAVehicle {
        if vehicleID == nil {
            Logger.error("OBARawVehicleStatus missing vehicleID")
        }
        return OBAVehicle(
            id: vehicleID ?? "unknown",
            lastUpdateTime: lastUpdateTime,
            lastLocationUpdateTime: lastLocationUpdateTime,
            latitude: latitude,
            longitude: longitude,
            phase: phase,
            status: status,
            tripID: tripID,
            routeShortName: routeShortName,
            tripHeadsign: tripHeadsign
        )
    }
}

struct OBARawStopsForRouteResponse: Decodable, Sendable {
    let data: OBARawStopsForRoute

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dataContainer = try? container.decode(OBARawStopsForRoute.self, forKey: .data) {
            self.data = dataContainer
        } else if let entryContainer = try? container.decode(OBARawStopsForRoute.DataContainer.self, forKey: .data) {
            // Some deployments have a double "data" or "entry" wrapper
            let stopGroupings = entryContainer.entry?.stopGroupings ?? entryContainer.stopGroupings
            self.data = OBARawStopsForRoute(
                references: entryContainer.references,
                entry: entryContainer.entry,
                polylines: entryContainer.polylines,
                stopGroupings: stopGroupings
            )
        } else {
            // Fallback for missing/null data
            Logger.warn("OBARawStopsForRouteResponse: Unable to decode data container, falling back to empty data")
            self.data = OBARawStopsForRoute(references: nil, entry: nil, polylines: nil, stopGroupings: nil)
        }
    }
}

struct OBARawStopsForRoute: Decodable, Sendable {
    let references: References?
    let entry: Entry?
    let polylines: [Polyline]?
    let stopGroupings: [StopGrouping]?

    struct DataContainer: Decodable, Sendable {
        let references: References?
        let entry: Entry?
        let polylines: [Polyline]?
        let stopGroupings: [StopGrouping]?
    }

    struct Polyline: Decodable, Sendable {
        let points: String?
    }

    struct References: Decodable, Sendable {
        let stops: [RawStop]?
    }

    struct RawStop: Decodable, Sendable {
        let id: OBAStopID?
        let name: String?
        let lat: Double?
        let lon: Double?
        let code: String?
    }

    struct Entry: Decodable, Sendable {
        let stopGroupings: [StopGrouping]?
    }

    struct StopGrouping: Decodable, Sendable {
        let stopGroups: [StopGroup]?
        
        private enum CodingKeys: String, CodingKey {
            case stopGroups
            case ordered
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.stopGroups = try container.decodeIfPresent([StopGroup].self, forKey: .stopGroups)
        }
    }

    struct StopGroup: Decodable, Sendable {
        let id: String?
        let name: Name?
        let stopIDs: [OBAStopID]?
        let polylines: [Polyline]?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case stopIds
            case stopIDs
            case polylines
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(String.self, forKey: .id)
            self.name = try container.decodeIfPresent(Name.self, forKey: .name)
            self.stopIDs = (try? container.decodeIfPresent([OBAStopID].self, forKey: .stopIds))
                ?? (try? container.decodeIfPresent([OBAStopID].self, forKey: .stopIDs))
            self.polylines = try container.decodeIfPresent([Polyline].self, forKey: .polylines)
        }
    }

    struct Name: Decodable, Sendable {
        let name: String?
    }

    func toDomainDirections() -> [OBARouteDirection] {
        // Index stops by ID for quick lookup, handling potential duplicates safely.
        var stopByID: [OBAStopID: OBAStop] = [:]
        for raw in (references?.stops ?? []) {
            guard let id = raw.id else { continue }
            stopByID[id] = OBAStop(
                id: id,
                name: raw.name ?? "Unknown",
                latitude: raw.lat ?? 0.0,
                longitude: raw.lon ?? 0.0,
                code: raw.code
            )
        }

        let groupings = stopGroupings ?? entry?.stopGroupings ?? []
        return groupings.flatMap { grouping in
            (grouping.stopGroups ?? []).compactMap { group -> OBARouteDirection? in
                guard let stops = group.stopIDs?.compactMap({ stopByID[$0] }) else { return nil }
                return OBARouteDirection(
                    id: group.id ?? UUID().uuidString,
                    name: group.name?.name ?? "Unknown",
                    stops: stops
                )
            }
        }.filter { !$0.stops.isEmpty }
    }
}

/// Thin DTO for the `stop` API.
struct OBARawStopResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let id: OBAStopID?
        let name: String?
        let lat: Double?
        let lon: Double?
        let code: String?
        let direction: String?
        let routes: [OBARawRoutesForLocationResponse.RawRoute]?
        let entry: StopEntry?
        let stop: StopEntry?
        let references: References?
    }
    
    struct StopEntry: Decodable, Sendable {
        let id: OBAStopID?
        let name: String?
        let lat: Double?
        let lon: Double?
        let code: String?
        let direction: String?
        let routes: [OBARawRoutesForLocationResponse.RawRoute]?

        private enum CodingKeys: String, CodingKey {
            case id, name, lat, lon, code, direction, routes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(OBAStopID.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            lat = try container.decodeIfPresent(Double.self, forKey: .lat)
            lon = try container.decodeIfPresent(Double.self, forKey: .lon)
            direction = try container.decodeIfPresent(String.self, forKey: .direction)
            routes = try container.decodeIfPresent([OBARawRoutesForLocationResponse.RawRoute].self, forKey: .routes)

            if let s = try? container.decodeIfPresent(String.self, forKey: .code) {
                code = s
            } else if let i = try? container.decodeIfPresent(Int.self, forKey: .code) {
                code = String(i)
            } else {
                code = nil
            }
        }
    }

    struct References: Decodable, Sendable {
        let routes: [OBARawRoutesForLocationResponse.RawRoute]?
    }
    
    let data: Data

    func toDomainStop() -> OBAStop {
        let stopID = data.entry?.id ?? data.stop?.id ?? data.id
        let name = data.entry?.name ?? data.stop?.name ?? data.name
        let lat = data.entry?.lat ?? data.stop?.lat ?? data.lat
        let lon = data.entry?.lon ?? data.stop?.lon ?? data.lon
        
        if stopID == nil || name == nil || lat == nil || lon == nil {
            Logger.error("OBARawStopResponse missing critical data: id=\(String(describing: stopID)), name=\(String(describing: name)), lat=\(String(describing: lat)), lon=\(String(describing: lon))")
        }

        let code = data.entry?.code ?? data.stop?.code ?? data.code
        let direction = data.entry?.direction ?? data.stop?.direction ?? data.direction
        
        return OBAStop(
            id: stopID ?? "unknown",
            name: name ?? "Unknown",
            latitude: lat ?? 0.0,
            longitude: lon ?? 0.0,
            code: code,
            direction: direction
        )
    }

    func toDomainRoutes() -> [OBARoute] {
        let routes = data.entry?.routes ?? data.stop?.routes ?? data.routes ?? data.references?.routes ?? []
        return routes.map { raw in
            OBARoute(
                id: raw.id,
                shortName: raw.shortName,
                longName: raw.longName?.isEmpty == false ? raw.longName : raw.description
            )
        }
    }
}

/// Thin DTO for the `trip` API.
struct OBARawTripDetails: Decodable, Sendable {
    let id: OBATripID?
    let routeID: OBARouteID?
    let tripHeadsign: String?
    let serviceID: String?
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
        if id == nil || routeID == nil {
            Logger.error("OBARawTripDetails missing critical IDs: id=\(String(describing: id)), routeID=\(String(describing: routeID))")
        }
        return OBATripDetails(
            id: id ?? "unknown",
            routeID: routeID ?? "unknown",
            headsign: tripHeadsign,
            serviceID: serviceID ?? "unknown",
            shapeID: shapeID,
            directionID: directionID,
            blockID: blockID
        )
    }
}

/// Raw envelope for the `trip-details` API.
struct OBARawTripDetailsResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: OBATripExtendedDetails?
        let tripDetails: OBATripExtendedDetails?
        let references: References?
    }

    struct References: Decodable, Sendable {
        let stops: [RawStop]?
    }

    struct RawStop: Decodable, Sendable {
        let id: String?
        let name: String?
        let lat: Double?
        let lon: Double?
    }

    let data: Data
}

struct OBARawScheduleForStopResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let entry: Entry
    }
    struct Entry: Decodable, Sendable {
        let stopId: String?
        let date: Double?
        let stopRouteSchedules: [StopRouteSchedule]?
    }
    struct StopRouteSchedule: Decodable, Sendable {
        let stopRouteDirectionSchedules: [StopRouteDirectionSchedule]
    }
    struct StopRouteDirectionSchedule: Decodable, Sendable {
        let scheduleStopTimes: [StopScheduleStopTime]
    }
    struct StopScheduleStopTime: Decodable, Sendable {
        let tripId: String?
        let arrivalTime: Int64?
        let departureTime: Int64?
        let stopHeadsign: String?
    }
    private let data: Data
    func toDomainSchedule() -> OBAStopSchedule {
        let schedules = data.entry.stopRouteSchedules ?? []
        let directionSchedules = schedules.flatMap { $0.stopRouteDirectionSchedules }
        let stopTimes = directionSchedules.flatMap { $0.scheduleStopTimes }

        let domainTimes = stopTimes.map { raw -> OBAStopScheduleStopTime in
            let tripID = raw.tripId ?? "unknown"
            let arrivalDate = Date(timeIntervalSince1970: Double(raw.arrivalTime ?? 0) / 1000.0)
            let departureDate = Date(timeIntervalSince1970: Double(raw.departureTime ?? 0) / 1000.0)
            let headsign = (raw.stopHeadsign?.isEmpty == true) ? nil : raw.stopHeadsign

            return OBAStopScheduleStopTime(
                tripID: tripID,
                arrivalTime: arrivalDate,
                departureTime: departureDate,
                stopHeadsign: headsign
            )
        }

        let stopID = data.entry.stopId ?? "unknown"
        let scheduleDate = Date(timeIntervalSince1970: (data.entry.date ?? 0) / 1000.0)

        return OBAStopSchedule(
            stopID: stopID,
            date: scheduleDate,
            stopTimes: domainTimes
        )
    }
}

struct OBARawAgenciesWithCoverageResponse: Decodable, Sendable {
    struct DataContainer: Decodable, Sendable {
        let list: [AgencyRaw]
    }
    struct AgencyRaw: Decodable, Sendable {
        let agencyId: String?
        let agency: AgencyInfo?
        let lat: Double?
        let lon: Double?
        let latSpan: Double?
        let lonSpan: Double?

        struct AgencyInfo: Decodable, Sendable {
            let id: String?
        }
    }
    
    private let list: [AgencyRaw]
    
    private enum CodingKeys: String, CodingKey {
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 1. Try to decode 'data' as a dictionary containing 'list'
        if let dataContainer = try? container.decode(DataContainer.self, forKey: .data) {
            self.list = dataContainer.list
        } 
        // 2. Try to decode 'data' as a direct array (common for MTA and some other servers)
        else if let list = try? container.decode([AgencyRaw].self, forKey: .data) {
            self.list = list
        } 
        else {
            Logger.warn("OBARawAgenciesWithCoverageResponse: Unable to decode data container, falling back to empty list")
            self.list = []
        }
    }

    func toDomainAgencies() -> [OBAAgencyCoverage] {
        list.map {
            OBAAgencyCoverage(
                agencyID: $0.agencyId ?? $0.agency?.id ?? "unknown",
                centerLatitude: $0.lat ?? 0.0,
                centerLongitude: $0.lon ?? 0.0
            )
        }
    }
}

struct OBARawRoutesForLocationResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [RawRoute]?
        let routes: [RawRoute]?
    }

    struct RawRoute: Decodable, Sendable {
        let id: String
        let shortName: String?
        let longName: String?
        let description: String?
    }

    let data: Data

    func toDomainRoutes() -> [OBARoute] {
        (data.list ?? data.routes ?? []).map { raw in
            OBARoute(
                id: raw.id,
                shortName: raw.shortName,
                longName: raw.longName?.isEmpty == false ? raw.longName : raw.description
            )
        }
    }
}

struct OBARawTripsForLocationResponse: Decodable, Sendable {
    struct Data: Decodable, Sendable {
        let list: [RawTrip]?
        let vehicles: [RawTrip]?
        let trips: [RawTrip]?
        let references: OBARawStopsForLocationResponse.ReferencesRaw?
    }

    struct RawTrip: Decodable, Sendable {
        let tripId: String
        let vehicleId: String?
        let lastUpdateTime: Date?
        let location: Location?
        let orientation: Double?
        let routeId: String?
        let routeShortName: String?
        let tripHeadsign: String?
        let scheduleDeviation: Int?
        let predicted: Bool?

        private enum CodingKeys: String, CodingKey {
            case tripId
            case vehicleId
            case lastUpdateTime
            case location
            case orientation
            case routeId
            case routeShortName
            case tripHeadsign
            case scheduleDeviation
            case predicted
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.tripId = try container.decode(String.self, forKey: .tripId)
            self.vehicleId = try container.decodeIfPresent(String.self, forKey: .vehicleId)
            self.lastUpdateTime = try container.decodeIfPresent(Date.self, forKey: .lastUpdateTime)
            self.location = try container.decodeIfPresent(Location.self, forKey: .location)
            self.orientation = try container.decodeIfPresent(Double.self, forKey: .orientation)
            self.routeId = try container.decodeIfPresent(String.self, forKey: .routeId)
            self.routeShortName = try container.decodeIfPresent(String.self, forKey: .routeShortName)
            self.tripHeadsign = try container.decodeIfPresent(String.self, forKey: .tripHeadsign)
            self.scheduleDeviation = try container.decodeIfPresent(Int.self, forKey: .scheduleDeviation)
            self.predicted = try container.decodeIfPresent(Bool.self, forKey: .predicted)
        }

        struct Location: Decodable, Sendable {
            let lat: Double
            let lon: Double
        }
    }

    let data: Data

    func toDomain() -> [OBATripForLocation] {
        let trips = data.list ?? data.vehicles ?? data.trips ?? []
        let routeMap = Dictionary(uniqueKeysWithValues: (data.references?.routes ?? []).compactMap { route in
            return (route.id, route)
        })

        return trips.map { raw in
            var routeShortName = raw.routeShortName
            let tripHeadsign = raw.tripHeadsign

            if let routeId = raw.routeId, let route = routeMap[routeId] {
                if routeShortName == nil || routeShortName!.isEmpty {
                    routeShortName = route.shortName ?? route.longName
                }
            }

            return OBATripForLocation(
                id: raw.tripId,
                vehicleID: raw.vehicleId ?? "",
                latitude: raw.location?.lat,
                longitude: raw.location?.lon,
                orientation: raw.orientation,
                routeID: raw.routeId,
                routeShortName: routeShortName,
                tripHeadsign: tripHeadsign,
                lastUpdateTime: raw.lastUpdateTime,
                scheduleDeviation: raw.scheduleDeviation,
                predicted: raw.predicted
            )
        }
    }
}

struct OBARawStopsForLocationResponse: Decodable, Sendable {
    struct DataContainer: Decodable, Sendable {
        let list: [StopRaw]?
        let stops: [StopRaw]?
        let references: ReferencesRaw?

        var allStops: [StopRaw] {
            list ?? stops ?? []
        }
    }

    struct StopRaw: Decodable, Sendable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
        let code: String?
        let direction: String?
        let routeIds: [String]?
        let locationType: Int?
    }

    struct ReferencesRaw: Decodable, Sendable {
        let routes: [OBARawRoutesForLocationResponse.RawRoute]?
    }

    let data: DataContainer

    func toDomainStops() -> [OBAStop] {
        data.allStops.map {
            OBAStop(
                id: $0.id,
                name: $0.name,
                latitude: $0.lat,
                longitude: $0.lon,
                code: $0.code,
                direction: $0.direction,
                locationType: $0.locationType
            )
        }
    }

    func stopIDToRouteNames() -> [OBAStopID: String] {
        var result: [OBAStopID: String] = [:]
        let routeMap = Dictionary<String, String>(uniqueKeysWithValues: (data.references?.routes ?? []).compactMap { route in
            return (route.id, route.shortName ?? route.longName ?? "")
        })

        for stop in data.allStops {
            if let routeIds = stop.routeIds {
                let names = routeIds.compactMap { routeMap[$0] }
                result[stop.id] = names.joined(separator: ", ")
            }
        }
        return result
    }
}
