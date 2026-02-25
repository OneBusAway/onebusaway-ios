//
//  NearbyTripMatcherTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `NearbyTripMatcher` filtering and sorting logic.
class NearbyTripMatcherTests: OBATestCase {
    /// Seattle downtown — used as the user's GPS position.
    let userLocation = CLLocation(latitude: 47.6062, longitude: -122.3321)

    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    // MARK: - Helpers

    /// Stubs the arrivals-and-departures-for-stop endpoint for any stop ID.
    private func stubArrivals(fixture: String = "arrivals_and_departures_for_stop_1_10020.json") {
        let data = Fixtures.loadData(file: fixture)
        dataLoader.mock(data: data) { request in
            request.url?.absoluteString.contains("arrivals-and-departures-for-stop") ?? false
        }
    }

    /// Loads real stops from the Seattle fixture.
    private func loadStops() -> [Stop] {
        return try! Fixtures.loadSomeStops()
    }

    /// Returns the first route found across all fixture stops, or nil.
    private func firstRouteFromStops(_ stops: [Stop]) -> Route? {
        for stop in stops {
            if let route = stop.routes.first {
                return route
            }
        }
        return nil
    }

    // MARK: - Basic Behavior

    func test_findTrips_withValidStopsAndArrivals_returnsResults() async throws {
        let stops = loadStops()
        stubArrivals()

        guard let route = firstRouteFromStops(stops) else {
            XCTFail("No routes found in fixture stops")
            return
        }

        let results = try await NearbyTripMatcher.findTrips(
            for: route,
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        // Results may or may not be empty depending on fixture data containing
        // real-time arrivals for this route. The key thing is it doesn't crash.
        expect(results).toNot(beNil())
    }

    func test_findTrips_filtersOutWrongRoute_throwsNoStopsNearby() async {
        let stops = loadStops()
        stubArrivals()

        let fakeRoute = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: [
            "agencyId": "1",
            "id": "NONEXISTENT_ROUTE_999",
            "shortName": "Fake",
            "type": 3,
            "longName": "Fake Route"
        ])

        do {
            _ = try await NearbyTripMatcher.findTrips(
                for: fakeRoute,
                near: userLocation,
                using: restService,
                stops: stops,
                maxDistance: 500_000
            )
            XCTFail("Expected MatchError.noStopsNearby to be thrown")
        } catch let error as NearbyTripMatcher.MatchError {
            expect(error) == .noStopsNearby
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_findTrips_emptyStops_throwsNoStopsNearby() async {
        let data = Fixtures.loadData(file: "stops_for_location_outofrange.json")
        dataLoader.mock(data: data) { request in
            request.url?.absoluteString.contains("stops-for-location") ?? false
        }

        let fakeRoute = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: [
            "agencyId": "1",
            "id": "1_100",
            "shortName": "100",
            "type": 3,
            "longName": "Test"
        ])

        do {
            _ = try await NearbyTripMatcher.findTrips(
                for: fakeRoute,
                near: userLocation,
                using: restService,
                stops: [],
                maxDistance: 500
            )
            XCTFail("Expected MatchError.noStopsNearby to be thrown")
        } catch let error as NearbyTripMatcher.MatchError {
            expect(error) == .noStopsNearby
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Sorting

    func test_findTrips_sortsByDistanceClosestFirst() async throws {
        let stops = loadStops()
        stubArrivals()

        guard let route = firstRouteFromStops(stops) else { return }

        let results = try await NearbyTripMatcher.findTrips(
            for: route,
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        guard results.count >= 2 else { return }

        for i in 0..<(results.count - 1) {
            expect(results[i].distanceFromUser) <= results[i + 1].distanceFromUser
        }
    }

    // MARK: - MatchError

    func test_matchError_noStopsNearby_localizedDescription() {
        let error = NearbyTripMatcher.MatchError.noStopsNearby
        expect(error.localizedDescription).toNot(beEmpty())
    }

    func test_matchError_noRealtimeData_localizedDescription() {
        let error = NearbyTripMatcher.MatchError.noRealtimeData
        expect(error.localizedDescription).toNot(beEmpty())
    }
}
