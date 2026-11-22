//
//  RESTTripSuggestionDataSource.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore

/// Trip suggestions' vehicles from the OBA REST API.
///
/// Uses `stops-for-location`, `arrivals-and-departures-for-stop` and `trip-details`,
/// which every OBA server supports. Every request skips the URL cache: a cached
/// response would make a fix look fresher than it is, and the matcher carries each
/// fix forward by its age.
final class RESTTripSuggestionDataSource: TripSuggestionDataSource {
    private let apiService: RESTAPIService
    /// The closest stops to ask for arrivals. Each is one request.
    private let stopLimit: Int

    init(apiService: RESTAPIService, stopLimit: Int = 4) {
        self.apiService = apiService
        self.stopLimit = stopLimit
    }

    func nearbyVehicles(around coordinate: CLLocationCoordinate2D) async throws -> [TripSuggestionCandidate] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let stops = try await apiService.getStops(coordinate: coordinate).list
            .sorted { location.distance(from: $0.location) < location.distance(from: $1.location) }
            .prefix(stopLimit)

        var vehicles = [TripSuggestionCandidate]()
        var seen = Set<String>()
        var anySucceeded = false
        var lastError: Error?
        for stop in stops {
            // URLSession reports a cancelled request as `URLError.cancelled`, not
            // `CancellationError`, so check the task itself before each request.
            try Task.checkCancellation()
            do {
                let arrivals = try await apiService.getArrivalsAndDeparturesForStop(
                    id: stop.id,
                    minutesBefore: 5,
                    // The rider's own vehicle is due within minutes or has just left.
                    minutesAfter: 10,
                    cachePolicy: .reloadIgnoringLocalCacheData
                ).entry.arrivalsAndDepartures
                anySucceeded = true
                for arrival in arrivals {
                    guard let candidate = Self.candidate(from: arrival),
                          seen.insert(candidate.id).inserted else { continue }
                    vehicles.append(candidate)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                lastError = error
            }
        }
        if !anySucceeded, let lastError {
            throw lastError
        }
        return vehicles
    }

    func currentSighting(of candidate: TripSuggestionCandidate) async throws -> VehicleSighting? {
        let details = try await apiService.getTrip(
            tripID: candidate.tripID,
            vehicleID: candidate.vehicleID,
            serviceDate: candidate.serviceDate,
            cachePolicy: .reloadIgnoringLocalCacheData
        ).entry
        guard let status = details.status else { return nil }
        return VehicleSighting(tripStatus: status, tripID: candidate.tripID)
    }

    static func candidate(from arrival: ArrivalDeparture) -> TripSuggestionCandidate? {
        guard let status = arrival.tripStatus,
              let sighting = VehicleSighting(tripStatus: status, tripID: arrival.tripID) else { return nil }
        let route = arrival.route
        return TripSuggestionCandidate(
            id: arrival.vehicleID ?? arrival.tripID,
            tripID: arrival.tripID,
            vehicleID: arrival.vehicleID,
            routeShortName: arrival.routeShortName,
            headsign: arrival.tripHeadsign,
            routeType: route?.routeType ?? .unknown,
            agencyName: route?.agency?.name,
            routeColor: route?.color,
            routeTextColor: route?.textColor,
            serviceDate: arrival.serviceDate,
            sighting: sighting,
            arrivalDeparture: arrival
        )
    }
}
