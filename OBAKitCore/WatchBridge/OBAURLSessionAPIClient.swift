//
//  OBAURLSessionAPIClient.swift
//  OBAKitCore
//
//  Created by Prince Yadav on 01/01/26.
//

import Foundation
import CoreLocation

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
            minutesAfterArrivals: UInt = 125
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
        let path = "/api/where/arrival-and-departure-for-stop/\(stopID).json"
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

        let url = try buildURL(path: path, queryItems: params)
        let response: OBARawListResponse<OBARawArrival> = try await get(url: url)
        return response.list.toDomainArrival()
    }

    public func fetchStop(id: OBAStopID) async throws -> OBAStop {
        let path = "/api/where/stop/\(id).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawStopResponse = try await get(url: url)
        return response.toDomainStop()
    }

    public func fetchScheduleForStop(
        stopID: OBAStopID,
        date: Date?
    ) async throws -> OBAStopSchedule {
        let path = "/api/where/schedule-for-stop/\(stopID).json"
        var items = apiKeyQueryItem
        if let date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "date", value: formatter.string(from: date)))
        }
        let url = try buildURL(path: path, queryItems: items)
        let response: OBARawScheduleForStopResponse = try await get(url: url)
        return response.toDomainSchedule()
    }

    public func fetchAgenciesWithCoverage() async throws -> [OBAAgencyCoverage] {
        let path = "/api/where/agencies-with-coverage.json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawAgenciesWithCoverageResponse = try await get(url: url)
        return response.toDomainAgencies()
    }

    public func submitStopProblem(_ report: OBAStopProblemReport) async throws {
        let path = "/api/where/report-problem-with-stop/\(report.stopID).json"
        var items = apiKeyQueryItem + [
            URLQueryItem(name: "code", value: report.code),
        ]
        if let comment = report.comment, !comment.isEmpty {
            items.append(URLQueryItem(name: "userComment", value: comment))
        }
        if let lat = report.locationLatitude, let lon = report.locationLongitude {
            items.append(contentsOf: [
                URLQueryItem(name: "userLat", value: String(lat)),
                URLQueryItem(name: "userLon", value: String(lon))
            ])
            if let accuracy = report.locationHorizontalAccuracy {
                items.append(URLQueryItem(name: "userLocationAccuracy", value: String(accuracy)))
            }
        }
        let url = try buildURL(path: path, queryItems: items)
        let request = buildRequest(url: url)
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OBAAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, url: url)
        }
    }

    public func submitTripProblem(_ report: OBATripProblemReport) async throws {
        let path = "/api/where/report-problem-with-trip.json"
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
        if let lat = report.locationLatitude, let lon = report.locationLongitude {
            items.append(contentsOf: [
                URLQueryItem(name: "userLat", value: String(lat)),
                URLQueryItem(name: "userLon", value: String(lon))
            ])
            if let accuracy = report.locationHorizontalAccuracy {
                items.append(URLQueryItem(name: "userLocationAccuracy", value: String(accuracy)))
            }
        }
        let url = try buildURL(path: path, queryItems: items)
        let request = buildRequest(url: url)
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OBAAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, url: url)
        }
    }

    public func fetchNearbyStops(
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> OBANearbyStopsResult {
        let path = "/api/where/stops-for-location.json"

        // Use a larger radius for MTA or if zero results, or use latSpan/lonSpan
        let finalRadius = radius > 0 ? radius : 1000.0

        let queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "latSpan", value: "0.05"), // ~5km span
            URLQueryItem(name: "lonSpan", value: "0.05"),
            URLQueryItem(name: "radius", value: String(finalRadius))
        ] + apiKeyQueryItem

        let url = try buildURL(path: path, queryItems: queryItems)
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
        let path = "/api/where/stops-for-location.json"
        let queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "query", value: query)
        ] + apiKeyQueryItem

        let url = try buildURL(path: path, queryItems: queryItems)
        let response: OBARawStopsForLocationResponse = try await get(url: url)
        return OBANearbyStopsResult(
            stops: response.toDomainStops(),
            stopIDToRouteNames: response.stopIDToRouteNames()
        )
    }

    public func fetchArrivals(for stopID: OBAStopID) async throws -> OBAArrivalsResult {
        try await tryFallback([
            {
                let path = "/api/where/arrivals-and-departures-for-stop/\(stopID).json"
                let queryItems = self.apiKeyQueryItem + [
                    URLQueryItem(name: "minutesBefore", value: String(self.configuration.minutesBeforeArrivals)),
                    URLQueryItem(name: "minutesAfter", value: String(self.configuration.minutesAfterArrivals))
                ]
                let url = try self.buildURL(path: path, queryItems: queryItems)
                let response: OBARawListResponse<[OBARawArrival]> = try await self.get(url: url)
                return self.mapArrivalsResponse(response)
            },
            {
                let path = "/api/where/arrivals-and-departures-for-stop.json"
                let queryItems = self.apiKeyQueryItem + [
                    URLQueryItem(name: "stopId", value: stopID),
                    URLQueryItem(name: "minutesBefore", value: String(self.configuration.minutesBeforeArrivals)),
                    URLQueryItem(name: "minutesAfter", value: String(self.configuration.minutesAfterArrivals))
                ]
                let url = try self.buildURL(path: path, queryItems: queryItems)
                let response: OBARawListResponse<[OBARawArrival]> = try await self.get(url: url)
                return self.mapArrivalsResponse(response)
            },
            {
                let path = "/api/where/stop/\(stopID).json"
                let url = try self.buildURL(path: path, queryItems: self.apiKeyQueryItem)
                let response: OBARawStopResponse = try await self.get(url: url)
                let domainStop = response.toDomainStop()
                return OBAArrivalsResult(
                    arrivals: [],
                    routes: response.toDomainRoutes(),
                    stopName: domainStop.name,
                    stopCode: domainStop.code,
                    stopDirection: domainStop.direction
                )
            }
        ])
    }

    private func mapArrivalsResponse(_ response: OBARawListResponse<[OBARawArrival]>) -> OBAArrivalsResult {
        let now = Date()
        let arrivals = response.list.map { $0.toDomainArrival(referenceDate: now) }
        let routes = response.toDomainRoutes()
        return OBAArrivalsResult(
            arrivals: arrivals,
            routes: routes,
            stopName: response.stop?.name,
            stopCode: response.stop?.code,
            stopDirection: response.stop?.direction
        )
    }

    public func fetchTripsForLocation(
        latitude: Double,
        longitude: Double,
        latSpan: Double,
        lonSpan: Double
    ) async throws -> [OBATripForLocation] {
        let path = "/api/where/trips-for-location.json"

        // Use provided spans or default to ~1km if zero
        let finalLatSpan = latSpan > 0 ? latSpan : 0.01
        let finalLonSpan = lonSpan > 0 ? lonSpan : 0.01

        let queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "latSpan", value: String(finalLatSpan)),
            URLQueryItem(name: "lonSpan", value: String(finalLonSpan)),
            URLQueryItem(name: "includeStatus", value: "true")
        ] + apiKeyQueryItem

        let url = try buildURL(path: path, queryItems: queryItems)
        let response: OBARawTripsForLocationResponse = try await get(url: url)
        return response.toDomain()
    }

    public func fetchTripsForRoute(routeID: OBARouteID) async throws -> [OBATripForLocation] {
        let path = "/api/where/trips-for-route/\(routeID).json"
        let queryItems = [
            URLQueryItem(name: "includeStatus", value: "true")
        ] + apiKeyQueryItem

        let url = try buildURL(path: path, queryItems: queryItems)
        let response: OBARawTripsForLocationResponse = try await get(url: url)
        return response.toDomain()
    }

    public func fetchRoutesForStop(stopID: OBAStopID) async throws -> [OBARoute] {
        try await tryFallback([
            {
                let path = "/api/where/routes-for-stop/\(stopID).json"
                let url = try self.buildURL(path: path, queryItems: self.apiKeyQueryItem)
                let response: OBARawRoutesForStopResponse = try await self.get(url: url)
                return response.toDomainRoutes()
            },
            {
                let path = "/api/where/routes-for-stop.json"
                let queryItems = self.apiKeyQueryItem + [URLQueryItem(name: "stopId", value: stopID)]
                let url = try self.buildURL(path: path, queryItems: queryItems)
                let response: OBARawRoutesForStopResponse = try await self.get(url: url)
                return response.toDomainRoutes()
            },
            {
                let stopPath = "/api/where/stop/\(stopID).json"
                let stopURL = try self.buildURL(path: stopPath, queryItems: self.apiKeyQueryItem)
                let response: OBARawStopResponse = try await self.get(url: stopURL)
                return response.toDomainRoutes()
            },
            {
                let arrivalsPath = "/api/where/arrivals-and-departures-for-stop/\(stopID).json"
                let arrivalsURL = try self.buildURL(path: arrivalsPath, queryItems: self.apiKeyQueryItem)
                let response: OBARawListResponse<[OBARawArrival]> = try await self.get(url: arrivalsURL)
                return response.toDomainRoutes()
            }
        ])
    }

    public func searchRoutes(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) async throws -> [OBARoute] {
        let path = "/api/where/routes-for-location.json"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(radius))
        ]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        let queryItems = items + apiKeyQueryItem

        let url = try buildURL(path: path, queryItems: queryItems)
        let response: OBARawRoutesForLocationResponse = try await get(url: url)
        return response.toDomainRoutes()
    }

    public func fetchStopsForRoute(routeID: OBARouteID) async throws -> [OBARouteDirection] {
        try await tryFallback([
            {
                let path = "/api/where/stops-for-route/\(routeID).json"
                let url = try self.buildURL(path: path, queryItems: self.apiKeyQueryItem + [URLQueryItem(name: "includePolylines", value: "false")])
                let response: OBARawStopsForRouteResponse = try await self.get(url: url)
                return response.data.toDomainDirections()
            },
            {
                let path = "/api/where/stops-for-route.json"
                let queryItems = self.apiKeyQueryItem + [
                    URLQueryItem(name: "routeId", value: routeID),
                    URLQueryItem(name: "includePolylines", value: "false")
                ]
                let url = try self.buildURL(path: path, queryItems: queryItems)
                let response: OBARawStopsForRouteResponse = try await self.get(url: url)
                return response.data.toDomainDirections()
            }
        ])
    }

    public func fetchShapeIDForRoute(routeID: OBARouteID) async throws -> String? {
        let path = "/api/where/schedule-for-route/\(routeID).json"
        do {
            let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
            let response: OBARawScheduleForRouteResponse = try await get(url: url)
            return response.firstShapeID()
        } catch {
            Logger.error("schedule-for-route failed for \(routeID): \(error.localizedDescription)")
            return nil
        }
    }

    public func fetchShape(shapeID: String) async throws -> String {
        try await tryFallback([
            {
                let path = "/api/where/shape/\(shapeID).json"
                let url = try self.buildURL(path: path, queryItems: self.apiKeyQueryItem)
                let response: OBARawShapeResponse = try await self.get(url: url)
                return response.data.entry.points
            },
            {
                let path = "/api/where/stops-for-route/\(shapeID).json"
                let url = try self.buildURL(path: path, queryItems: self.apiKeyQueryItem + [URLQueryItem(name: "includePolylines", value: "true")])
                let response: OBARawStopsForRouteResponse = try await self.get(url: url)
                var points = (response.data.polylines ?? []).compactMap { $0.points }.joined()
                if points.isEmpty {
                    let groupings = response.data.stopGroupings ?? response.data.entry?.stopGroupings ?? []
                    points = groupings.flatMap { $0.stopGroups ?? [] }
                                     .flatMap { $0.polylines ?? [] }
                                     .compactMap { $0.points }
                                     .joined()
                }
                if points.isEmpty { throw OBAAPIError.notFound(url: url) }
                return points
            }
        ])
    }

    public func fetchVehicle(vehicleID: String) async throws -> OBAVehicle {
        let path = "/api/where/vehicle/\(vehicleID).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawListResponse<OBARawVehicleStatus> = try await get(url: url)

        // Handle potentially missing vehicle status in MTA response
        return response.list.toDomainVehicle()
    }

    public func fetchTrip(tripID: OBATripID) async throws -> OBATripDetails {
        let path = "/api/where/trip/\(tripID).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawListResponse<OBARawTripDetails> = try await get(url: url)
        return response.list.toDomain()
    }

    public func fetchTripForVehicle(vehicleID: String) async throws -> OBAVehicleTripStatus {
        let path = "/api/where/trip-for-vehicle/\(vehicleID).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawListResponse<OBAVehicleTripStatus> = try await get(url: url)
        return response.list
    }

    public func fetchTripDetails(tripID: OBATripID) async throws -> OBATripExtendedDetails {
        let path = "/api/where/trip-details/\(tripID).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)

        let response: OBARawTripDetailsResponse = try await get(url: url)

        // Handle potentially missing entry/schedule in MTA response
        guard let entry = response.data.entry ?? response.data.tripDetails else {
            throw OBAAPIError.badServerResponse(statusCode: 200, url: url)
        }

        var details = entry

        // Enhance stop times with names from references if needed
        if let stops = response.data.references?.stops, let schedule = details.schedule {
            let stopMapByID = Dictionary(uniqueKeysWithValues: stops.compactMap { stop -> (String, OBARawTripDetailsResponse.RawStop)? in
                guard let id = stop.id else { return nil }
                return (id, stop)
            })

            let enhancedStopTimes = schedule.stopTimes.map { stopTime -> OBATripExtendedDetails.StopTime in
                let rawStop = stopTime.stopId.flatMap { stopMapByID[$0] }

                // Prioritize headsign, but only if it's not nil or empty
                var name: String?
                if let stopHeadsign = stopTime.stopHeadsign, !stopHeadsign.isEmpty {
                    name = stopHeadsign
                } else {
                    // Fallback to raw stop name from references
                    name = rawStop?.name
                }

                return OBATripExtendedDetails.StopTime(
                    arrivalTime: stopTime.arrivalTime,
                    departureTime: stopTime.departureTime,
                    stopId: stopTime.stopId,
                    stopHeadsign: name,
                    distanceAlongTrip: stopTime.distanceAlongTrip,
                    historicalOccupancy: stopTime.historicalOccupancy,
                    latitude: rawStop?.lat,
                    longitude: rawStop?.lon
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

    /// Decodes an encoded polyline string into an array of coordinates.
    public static func decodePolyline(_ encodedPolyline: String) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D]()
        var index = encodedPolyline.startIndex
        var lat = 0
        var lon = 0

        while index < encodedPolyline.endIndex {
            func decodeNext() -> Int? {
                var result = 0
                var shift = 0
                var byte: Int
                repeat {
                    guard index < encodedPolyline.endIndex else { return nil }
                    guard let ascii = encodedPolyline[index].asciiValue else { break }
                    byte = Int(ascii) - 63
                    encodedPolyline.formIndex(after: &index)
                    result |= (byte & 0x1F) << shift
                    shift += 5
                } while byte >= 0x20
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }

            guard let dLat = decodeNext(), let dLon = decodeNext() else { break }
            lat += dLat
            lon += dLon
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) * 1e-5, longitude: Double(lon) * 1e-5))
        }
        return coords
    }

    public func fetchCurrentTime() async throws -> Date {
        let path = "/api/where/current-time.json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)

        // We only care about the top-level "currentTime" field in the JSON response,
        // but our generic `get` decodes a specific type.
        // Let's make a tiny local struct to capture the time.
        struct CurrentTimeResponse: Decodable {
            let currentTime: Date
        }

        let request = buildRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
             throw OBAAPIError.badServerResponse(statusCode: httpResponse.statusCode, url: url)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let result = try decoder.decode(CurrentTimeResponse.self, from: data)
            return result.currentTime
        } catch {
            throw OBAAPIError.decodingError(error, url: url)
        }
    }

    public func fetchVehiclesForAgency(agencyID: String) async throws -> [OBATripForLocation] {
        let path = "/api/where/vehicles-for-agency/\(agencyID).json"
        let url = try buildURL(path: path, queryItems: apiKeyQueryItem)
        let response: OBARawTripsForLocationResponse = try await get(url: url)
        return response.toDomain()
    }

    // MARK: - Helpers

    /// Correctly joins the base URL with a path and query items.
    /// This handles regions that have a path suffix in their base URL (e.g., /api/).
    internal func buildURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let baseURLString = configuration.baseURL.absoluteString
        let joinedURLString: String

        if baseURLString.hasSuffix("/") && path.hasPrefix("/") {
            joinedURLString = baseURLString + String(path.dropFirst())
        } else if !baseURLString.hasSuffix("/") && !path.hasPrefix("/") {
            joinedURLString = baseURLString + "/" + path
        } else {
            joinedURLString = baseURLString + path
        }

        guard var components = URLComponents(string: joinedURLString) else {
            throw OBAAPIError.invalidURL
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw OBAAPIError.invalidURL
        }

        return url
    }

    private var apiKeyQueryItem: [URLQueryItem] {
        if let key = configuration.apiKey, !key.isEmpty {
            return [URLQueryItem(name: "key", value: key)]
        }
        return []
    }

    private func buildRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func tryFallback<T>(_ closures: [() async throws -> T]) async throws -> T {
        var lastError: Error?
        for closure in closures {
            do {
                return try await closure()
            } catch {
                lastError = error
            }
        }
        if let lastError = lastError {
            throw lastError
        }
        throw OBAAPIError.invalidURL // Should not happen
    }

    private func get<Response: Decodable & Sendable>(url: URL) async throws -> Response {
        let request = buildRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299:
                // Success - proceed with decoding
                break
            case 404:
                throw OBAAPIError.notFound(url: url)
            case 400...499, 500...599:
                throw OBAAPIError.badServerResponse(statusCode: httpResponse.statusCode, url: url)
            default:
                throw OBAAPIError.badServerResponse(statusCode: httpResponse.statusCode, url: url)
            }
        }

        // Handle servers that return a literal `null` body for missing resources
        if data.count <= 6 {
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if s == "null" || s == "" {
                throw OBAAPIError.notFound(url: url)
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw OBAAPIError.decodingError(error, url: url)
        }
    }
}
