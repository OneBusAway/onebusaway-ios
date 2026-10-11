//
//  NearbyRouteDirections.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// One route in one direction. `direction` is the GTFS `direction_id` when
/// the agency publishes it, otherwise the trip headsign — so an agency without
/// direction IDs still gets one card per headsign rather than one per route.
public struct RouteDirectionKey: Hashable, Sendable {
    public let routeID: RouteID
    public let direction: String

    public init(routeID: RouteID, direction: String) {
        self.routeID = routeID
        self.direction = direction
    }

    init(arrival: ArrivalDeparture) {
        if let directionID = arrival.trip?.direction, !directionID.isEmpty {
            self.init(routeID: arrival.routeID, direction: "id:\(directionID)")
        } else {
            self.init(routeID: arrival.routeID, direction: "headsign:\(arrival.tripHeadsign ?? "")")
        }
    }
}

/// A stop serving a `NearbyRouteDirection`, with that direction's departures.
public struct RouteDirectionStop: Equatable, Identifiable {
    public let stop: Stop
    /// Meters from the origin the list was built around.
    public let distance: CLLocationDistance
    /// This route and direction only, soonest first. Never empty.
    public let departures: [ArrivalDeparture]

    public var id: StopID { stop.id }
}

/// A card on the watch's Nearby screen: a route, the way it is heading, and
/// the nearby stops where it can be caught.
public struct NearbyRouteDirection: Equatable, Identifiable {
    public let key: RouteDirectionKey
    public let route: Route
    /// The most common headsign among the departures, so trip variants
    /// ("Downtown Seattle", "Downtown Seattle via 35th Ave") share one label.
    public let headsign: String
    /// Nearest first. Never empty.
    public let stops: [RouteDirectionStop]

    public var id: RouteDirectionKey { key }
    public var nearestStop: RouteDirectionStop { stops[0] }
}

/// Builds the route-and-direction list from nearby stops' arrivals. Pure, so
/// the grouping rules are testable without a network or a clock.
public enum NearbyRouteDirections {

    /// Groups each stop's arrivals by route and direction.
    ///
    /// - Parameters:
    ///   - stops: The stops the arrivals were fetched for, in any order.
    ///   - arrivalsByStop: Upcoming arrivals per stop, already filtered (see
    ///     `BookmarkArrivalsRequest.matching`). A stop with no entry is skipped.
    ///   - origin: Where the user is; stops are ordered by distance from it.
    /// - Returns: Directions ordered by nearest stop, then soonest departure
    ///   there. A route with no upcoming departures at any of `stops` is absent:
    ///   its headsign is only known from a departure.
    public static func group(
        stops: [Stop],
        arrivalsByStop: [StopID: [ArrivalDeparture]],
        origin: CLLocation
    ) -> [NearbyRouteDirection] {
        let stopsByDistance = stops
            .map { (stop: $0, distance: $0.location.distance(from: origin)) }
            .sorted { $0.distance < $1.distance }

        var order = [RouteDirectionKey]()
        var routes = [RouteDirectionKey: Route]()
        var stopsByKey = [RouteDirectionKey: [RouteDirectionStop]]()

        for (stop, distance) in stopsByDistance {
            guard let arrivals = arrivalsByStop[stop.id] else { continue }

            var departuresByKey = [RouteDirectionKey: [ArrivalDeparture]]()
            var keysAtStop = [RouteDirectionKey]()
            for arrival in arrivals {
                let key = RouteDirectionKey(arrival: arrival)
                if departuresByKey[key] == nil { keysAtStop.append(key) }
                departuresByKey[key, default: []].append(arrival)
            }

            for key in keysAtStop {
                guard let route = departuresByKey[key]?.first?.route else { continue }
                let departures = (departuresByKey[key] ?? []).sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
                if routes[key] == nil {
                    order.append(key)
                    routes[key] = route
                }
                stopsByKey[key, default: []].append(RouteDirectionStop(stop: stop, distance: distance, departures: departures))
            }
        }

        let directions: [NearbyRouteDirection] = order.compactMap { key in
            guard let route = routes[key], let stops = stopsByKey[key], !stops.isEmpty else { return nil }
            return NearbyRouteDirection(key: key, route: route, headsign: headsign(for: stops, route: route), stops: stops)
        }

        return directions.sorted { lhs, rhs in
            if lhs.nearestStop.distance != rhs.nearestStop.distance {
                return lhs.nearestStop.distance < rhs.nearestStop.distance
            }
            let lhsNext = lhs.nearestStop.departures[0].arrivalDepartureDate
            let rhsNext = rhs.nearestStop.departures[0].arrivalDepartureDate
            if lhsNext != rhsNext { return lhsNext < rhsNext }
            // Deterministic order for equal times, so a refresh cannot shuffle cards.
            return (lhs.route.shortName, lhs.headsign) < (rhs.route.shortName, rhs.headsign)
        }
    }

    /// The same route heading another way, nearest first — the ⇆ target.
    public static func opposite(of key: RouteDirectionKey, in directions: [NearbyRouteDirection]) -> NearbyRouteDirection? {
        directions.first { $0.key.routeID == key.routeID && $0.key != key }
    }

    /// The most frequent headsign; ties go to the one departing soonest.
    private static func headsign(for stops: [RouteDirectionStop], route: Route) -> String {
        let departures = stops
            .flatMap(\.departures)
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }

        var counts = [String: Int]()
        var firstSeen = [String]()
        for departure in departures {
            guard let headsign = String.nilifyBlankValue(departure.tripHeadsign) else { continue }
            if counts[headsign] == nil { firstSeen.append(headsign) }
            counts[headsign, default: 0] += 1
        }

        // `max(by:)` keeps the last of equal maxima; reversing makes it the earliest.
        if let best = firstSeen.reversed().max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) {
            return best
        }
        return route.longName ?? route.shortName
    }
}

/// Fetches arrivals for nearby stops and groups them into route directions.
/// Stateless; the watch's Nearby screen calls it per location fix and the
/// route screen per poll.
public struct NearbyRoutesLoader: Sendable {
    /// Stops whose arrivals are fetched, nearest first: one request each.
    public let stopLimit: Int

    public init(stopLimit: Int = 8) {
        self.stopLimit = stopLimit
    }

    public func directions(near origin: CLLocation, using apiService: RESTAPIService) async throws -> [NearbyRouteDirection] {
        let stops = try await NearbyStopsLoader(limit: stopLimit).stops(near: origin.coordinate, using: apiService)
        guard !stops.isEmpty else { return [] }
        return try await directions(at: stops, origin: origin, using: apiService)
    }

    /// Throws only when **every** stop's fetch failed; a partial failure drops
    /// those stops and returns the rest.
    public func directions(at stops: [Stop], origin: CLLocation, using apiService: RESTAPIService) async throws -> [NearbyRouteDirection] {
        let requests = stops.map { BookmarkArrivalsRequest(stopID: $0.id) }
        var arrivalsByStop = [StopID: [ArrivalDeparture]]()
        var firstError: Error?

        for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: apiService) {
            switch result {
            case .success(let arrivals):
                arrivalsByStop[stopID] = BookmarkArrivalsRequest(stopID: stopID).matching(arrivals)
            case .failure(let error):
                Logger.error("NearbyRoutesLoader: arrivals failed for stop \(stopID): \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }

        if arrivalsByStop.isEmpty, let firstError {
            throw firstError
        }
        return NearbyRouteDirections.group(stops: stops, arrivalsByStop: arrivalsByStop, origin: origin)
    }
}
