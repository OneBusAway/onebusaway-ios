//
//  NearbyTripMatcher.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import os.log

/// Finds active trips for a given route near the user's location.
///
/// Uses `stops-for-location` + `arrivals-and-departures-for-stop` endpoints,
/// which are universally supported across OBA server deployments.
/// This is a stateless utility — no background tracking or battery drain.
public enum NearbyTripMatcher {

    private static let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "NearbyTripMatcher")

    /// Errors specific to trip matching.
    public enum MatchError: Error, LocalizedError, Equatable {
        case noStopsNearby
        case noRealtimeData

        public var errorDescription: String? {
            switch self {
            case .noStopsNearby:
                return "No stops found nearby."
            case .noRealtimeData:
                return "No real-time tracking data is available for this route."
            }
        }
    }

    /// The result of a successful trip match.
    public struct MatchResult {
        public let arrivalDeparture: ArrivalDeparture
        public let distanceFromUser: CLLocationDistance
    }

    /// Finds active, real-time vehicles on `route` near `userLocation`.
    ///
    /// - Parameters:
    ///   - route: The route selected by the user.
    ///   - userLocation: The user's current GPS location.
    ///   - apiService: The REST API service to query.
    ///   - stops: Nearby stops (from MapRegionManager cache). If empty, stops are fetched from the API.
    ///   - maxDistance: Maximum distance in meters between user and vehicle. Defaults to 500m.
    /// - Returns: Matching results sorted by distance (closest first).
    public static func findTrips(
        for route: Route,
        near userLocation: CLLocation,
        using apiService: RESTAPIService,
        stops: [Stop],
        maxDistance: CLLocationDistance = 500
    ) async throws -> [MatchResult] {
        let stopsForRoute = try await resolveStops(for: route, near: userLocation, using: apiService, stops: stops)
        let allArrivals = await fetchArrivals(for: stopsForRoute, userLocation: userLocation, using: apiService)
        return try filterAndSort(allArrivals, route: route, userLocation: userLocation, maxDistance: maxDistance)
    }

    // MARK: - Private Helpers

    /// Resolves stops serving the selected route, falling back to the API if cached stops are empty.
    private static func resolveStops(
        for route: Route,
        near userLocation: CLLocation,
        using apiService: RESTAPIService,
        stops: [Stop]
    ) async throws -> [Stop] {
        var nearbyStops = stops
        if nearbyStops.isEmpty {
            nearbyStops = try await apiService.getStops(coordinate: userLocation.coordinate).list
        }

        let stopsForRoute = nearbyStops.filter { stop in
            stop.routes.contains { $0.id == route.id }
        }

        guard !stopsForRoute.isEmpty else {
            throw MatchError.noStopsNearby
        }

        // Limit to 5 closest stops to avoid excessive API calls.
        return Array(
            stopsForRoute
                .sorted { userLocation.distance(from: $0.location) < userLocation.distance(from: $1.location) }
                .prefix(5)
        )
    }

    /// Fetches arrivals for each stop, continuing on individual stop failures.
    private static func fetchArrivals(
        for stops: [Stop],
        userLocation: CLLocation,
        using apiService: RESTAPIService
    ) async -> [ArrivalDeparture] {
        var allArrivals = [ArrivalDeparture]()

        for stop in stops {
            do {
                let response = try await apiService.getArrivalsAndDeparturesForStop(
                    id: stop.id,
                    minutesBefore: 5,
                    minutesAfter: 30
                )
                allArrivals.append(contentsOf: response.entry.arrivalsAndDepartures)
            } catch is CancellationError {
                break
            } catch {
                logger.error("Failed to fetch arrivals for stop \(stop.id): \(error)")
            }
        }

        return allArrivals
    }

    /// Filters arrivals by route, real-time status, and distance, then sorts by proximity.
    private static func filterAndSort(
        _ arrivals: [ArrivalDeparture],
        route: Route,
        userLocation: CLLocation,
        maxDistance: CLLocationDistance
    ) throws -> [MatchResult] {
        var seen = Set<String>()
        var matched = [MatchResult]()
        var hasNonRealtimeArrivals = false

        for arrival in arrivals {
            guard arrival.routeID == route.id else { continue }
            guard let tripStatus = arrival.tripStatus else { continue }

            if !tripStatus.isRealTime {
                hasNonRealtimeArrivals = true
                continue
            }

            guard let vehiclePosition = tripStatus.position else { continue }
            let distance = userLocation.distance(from: vehiclePosition)
            guard distance <= maxDistance else { continue }

            let vehicleKey = arrival.vehicleID ?? arrival.tripID
            guard seen.insert(vehicleKey).inserted else { continue }

            matched.append(MatchResult(arrivalDeparture: arrival, distanceFromUser: distance))
        }

        if matched.isEmpty && hasNonRealtimeArrivals {
            throw MatchError.noRealtimeData
        }

        return matched.sorted { $0.distanceFromUser < $1.distanceFromUser }
    }
}
