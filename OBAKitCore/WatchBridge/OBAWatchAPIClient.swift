//
//  OBAWatchAPIClient.swift
//  OBAKitCore
//
//  Created by Prince Yadav on 01/01/26.
//

import Foundation
import CoreLocation

// MARK: - API Client Protocol

/// A minimal, platform-agnostic API surface suitable for watchOS and iOS.
///
/// Implementations are responsible for talking to the real OneBusAway server
/// or a local cache, but they must remain Foundation-only.
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
    func fetchArrivals(for stopID: OBAStopID) async throws -> OBAArrivalsResult

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

    /// Fetches active trips (vehicles) for a specific route.
    /// - Parameter routeID: The route identifier.
    func fetchTripsForRoute(routeID: OBARouteID) async throws -> [OBATripForLocation]

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

    /// Fetches all active vehicles for a specific agency.
    func fetchVehiclesForAgency(agencyID: String) async throws -> [OBATripForLocation]
}

public extension OBAAPIClient {
    /// Fetches vehicles near a location with fallback to route-based search if location-based search returns no results.
    /// This is useful for servers that don't support `trips-for-location` or have strict limits.
    func fetchVehiclesReliably(
        latitude: Double,
        longitude: Double,
        latSpan: Double,
        lonSpan: Double
    ) async throws -> [OBATripForLocation] {
        var allVehicles: [OBATripForLocation] = []
        var seenIDs = Set<String>()
        var hasAnyLocation = false
        
        func addUnique(_ trips: [OBATripForLocation], filterByLocation: Bool = false) {
            for trip in trips {
                let id = trip.vehicleID.isEmpty ? trip.id : trip.vehicleID
                if !id.isEmpty && !seenIDs.contains(id) {
                    if filterByLocation, let lat = trip.latitude, let lon = trip.longitude {
                        let latDiff = abs(lat - latitude)
                        let lonDiff = abs(lon - longitude)
                        // Within roughly the requested span plus a buffer
                        if latDiff > latSpan * 1.5 || lonDiff > lonSpan * 1.5 {
                            continue
                        }
                    }
                    
                    seenIDs.insert(id)
                    allVehicles.append(trip)
                    if trip.latitude != nil && trip.longitude != nil {
                        hasAnyLocation = true
                    }
                }
            }
        }

        // 1. Try trips-for-location first
        do {
            let result = try await fetchTripsForLocation(
                latitude: latitude,
                longitude: longitude,
                latSpan: latSpan,
                lonSpan: lonSpan
            )
            addUnique(result)
        } catch {
            Logger.error("fetchTripsForLocation failed: \(error.localizedDescription)")
        }
        
        if !allVehicles.isEmpty && hasAnyLocation {
            return allVehicles
        }
        
        // 2. Fallback: Search for nearby routes and fetch vehicles for each in parallel
        let radius = max(latSpan, lonSpan) * 111000.0 // Convert degrees to meters roughly
        do {
            let nearbyRoutes = try await searchRoutes(
                query: "",
                latitude: latitude,
                longitude: longitude,
                radius: max(radius, 5000.0) // At least 5km
            )
            
            let routeTrips = await withTaskGroup(of: [OBATripForLocation].self) { group in
                for route in nearbyRoutes {
                    group.addTask {
                        do {
                            return try await self.fetchTripsForRoute(routeID: route.id)
                        } catch {
                            Logger.error("fetchTripsForRoute failed for \(route.id): \(error.localizedDescription)")
                            return []
                        }
                    }
                }
                
                var results: [OBATripForLocation] = []
                for await trips in group {
                    results.append(contentsOf: trips)
                }
                return results
            }
            
            addUnique(routeTrips)
        } catch {
            Logger.error("searchRoutes failed: \(error.localizedDescription)")
        }
        
        if !allVehicles.isEmpty && hasAnyLocation {
            return allVehicles
        }
        
        // 3. Last resort: Fetch all vehicles for agencies that have coverage near this location in parallel
        do {
            let agencies = try await fetchAgenciesWithCoverage()
            let nearbyAgencies = agencies.filter { agency in
                let latDiff = abs(agency.centerLatitude - latitude)
                let lonDiff = abs(agency.centerLongitude - longitude)
                // Within ~50km (roughly 0.5 degrees)
                return latDiff < 0.5 && lonDiff < 0.5
            }
            
            let agencyVehicles = await withTaskGroup(of: [OBATripForLocation].self) { group in
                for agency in nearbyAgencies {
                    group.addTask {
                        do {
                            return try await self.fetchVehiclesForAgency(agencyID: agency.agencyID)
                        } catch {
                            Logger.error("fetchVehiclesForAgency failed for \(agency.agencyID): \(error.localizedDescription)")
                            return []
                        }
                    }
                }
                
                var results: [OBATripForLocation] = []
                for await vehicles in group {
                    results.append(contentsOf: vehicles)
                }
                return results
            }
            
            addUnique(agencyVehicles, filterByLocation: true)
        } catch {
            Logger.error("fetchAgenciesWithCoverage failed: \(error.localizedDescription)")
        }
        
        return allVehicles
    }
}

// MARK: - API Errors

public enum OBAAPIError: LocalizedError, Sendable {
    case badServerResponse(statusCode: Int, url: URL)
    case notFound(url: URL)
    case decodingError(Error, url: URL)
    case invalidURL
    case other(Error)

    public var errorDescription: String? {
        switch self {
        case .badServerResponse(let statusCode, let url):
            return "Server returned error \(statusCode) for \(url.lastPathComponent)."
        case .notFound(let url):
            return "Resource not found: \(url.lastPathComponent)."
        case .decodingError(let error, let url):
            return "Unable to parse response from \(url.lastPathComponent): \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid request URL."
        case .other(let error):
            return error.localizedDescription
        }
    }
}
