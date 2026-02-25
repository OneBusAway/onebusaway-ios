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
///
/// Uses `arrivals_and_departures_for_stop_1_10020.json` which contains:
/// - Stop `1_10020` serving routes `1_30`, `1_65`, `1_74`
/// - 4 arrivals: 2 on route `1_30`, 2 on route `1_65`
/// - All have `predicted: true` (isRealTime) and vehicle positions
class NearbyTripMatcherTests: OBATestCase {
    /// Near stop 1_10020 in the fixture (NE 55th & 37th Ave NE).
    let userLocation = CLLocation(latitude: 47.6685, longitude: -122.2883)

    var dataLoader: MockDataLoader!

    override func setUp() {
        super.setUp()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    // MARK: - Helpers

    private let arrivalsFixture = "arrivals_and_departures_for_stop_1_10020.json"

    /// Stubs the arrivals-and-departures-for-stop endpoint.
    private func stubArrivals() {
        let data = Fixtures.loadData(file: arrivalsFixture)
        dataLoader.mock(data: data) { request in
            request.url?.absoluteString.contains("arrivals-and-departures-for-stop") ?? false
        }
    }

    /// Loads stops from the arrivals fixture's references (these have matching route IDs).
    private func stopsFromArrivalsFixture() -> [Stop] {
        let response = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture)
        // The stop from the entry + referenced stops both serve routes 1_30, 1_65.
        return [response.stop]
    }

    /// Gets route `1_30` from the arrivals fixture references.
    private func route30() -> Route {
        let stops = stopsFromArrivalsFixture()
        return stops.flatMap(\.routes).first { $0.id == "1_30" }!
    }

    /// Gets route `1_65` from the arrivals fixture references.
    private func route65() -> Route {
        let stops = stopsFromArrivalsFixture()
        return stops.flatMap(\.routes).first { $0.id == "1_65" }!
    }

    // MARK: - Positive Match

    func test_findTrips_returnsMatchesForRoute30() async throws {
        let stops = stopsFromArrivalsFixture()
        stubArrivals()

        let results = try await NearbyTripMatcher.findTrips(
            for: route30(),
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        // Fixture has 2 arrivals on route 1_30 with vehicles 1_7028 and 1_7022.
        expect(results.count) == 2
        let vehicleIDs = Set(results.compactMap { $0.arrivalDeparture.vehicleID })
        expect(vehicleIDs).to(contain("1_7028"))
        expect(vehicleIDs).to(contain("1_7022"))
    }

    func test_findTrips_returnsMatchesForRoute65() async throws {
        let stops = stopsFromArrivalsFixture()
        stubArrivals()

        let results = try await NearbyTripMatcher.findTrips(
            for: route65(),
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        // Fixture has 2 arrivals on route 1_65 with vehicles 1_3691 and 1_3674.
        expect(results.count) == 2
        let vehicleIDs = Set(results.compactMap { $0.arrivalDeparture.vehicleID })
        expect(vehicleIDs).to(contain("1_3691"))
        expect(vehicleIDs).to(contain("1_3674"))
    }

    // MARK: - Route Filtering

    func test_findTrips_nonexistentRoute_throwsNoStopsNearby() async {
        let stops = stopsFromArrivalsFixture()
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
            XCTFail("Expected MatchError.noStopsNearby")
        } catch let error as NearbyTripMatcher.MatchError {
            expect(error) == .noStopsNearby
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Distance Filtering

    func test_findTrips_tightDistance_excludesFarVehicles() async throws {
        let stops = stopsFromArrivalsFixture()
        stubArrivals()

        // 1 meter — should exclude all vehicles.
        let tightResults = try await NearbyTripMatcher.findTrips(
            for: route30(),
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 1
        )

        let wideResults = try await NearbyTripMatcher.findTrips(
            for: route30(),
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        expect(tightResults.count) < wideResults.count
        expect(tightResults).to(beEmpty())
        expect(wideResults.count) == 2
    }

    // MARK: - Sorting

    func test_findTrips_sortsByDistanceClosestFirst() async throws {
        let stops = stopsFromArrivalsFixture()
        stubArrivals()

        let results = try await NearbyTripMatcher.findTrips(
            for: route30(),
            near: userLocation,
            using: restService,
            stops: stops,
            maxDistance: 500_000
        )

        expect(results.count) >= 2
        for i in 0..<(results.count - 1) {
            expect(results[i].distanceFromUser) <= results[i + 1].distanceFromUser
        }
    }

    // MARK: - Empty Stops

    func test_findTrips_emptyStopsAndAPI_throwsNoStopsNearby() async {
        let data = Fixtures.loadData(file: "stops_for_location_outofrange.json")
        dataLoader.mock(data: data) { request in
            request.url?.absoluteString.contains("stops-for-location") ?? false
        }

        do {
            _ = try await NearbyTripMatcher.findTrips(
                for: route30(),
                near: userLocation,
                using: restService,
                stops: [],
                maxDistance: 500
            )
            XCTFail("Expected MatchError.noStopsNearby")
        } catch let error as NearbyTripMatcher.MatchError {
            expect(error) == .noStopsNearby
        } catch {
            XCTFail("Unexpected error: \(error)")
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
