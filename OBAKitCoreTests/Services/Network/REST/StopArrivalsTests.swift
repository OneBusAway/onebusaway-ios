//
//  StopArrivalsTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Foundation
import OBAKitCore

final class StopArrivalsTests: OBAKitCoreTestCase {
    let campusParkwayStopID = "1_10914"
    let galerStopID = "1_11370"
    let rvtdStopID = "1739_d1e8e68e-83f8-487f-baf5-f465fe70fc84.json"

    private func makeUrlString(stopID: StopID) -> String {
        "https://www.example.com/api/where/arrivals-and-departures-for-stop/\(stopID).json"
    }

    override func setUp() async throws {
        try await super.setUp()

        dataLoader.mock(
            URLString: makeUrlString(stopID: campusParkwayStopID),
            with: try Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        )

        dataLoader.mock(
            URLString: makeUrlString(stopID: galerStopID),
            with: try Fixtures.loadData(file: "arrivals_and_departures_for_stop_15th-galer.json")
        )

        dataLoader.mock(
            URLString: makeUrlString(stopID: rvtdStopID),
            with: try Fixtures.loadData(file: "arrivals-and-departures-for-stop-1739-rvtd.json")
        )
    }

    func testArrivalDepartureStatus() async throws {
        let arrivals = try await restAPIService.getArrivalsAndDeparturesForStop(id: galerStopID, minutesBefore: 5, minutesAfter: 30).entry

        XCTAssertEqual(arrivals.arrivalsAndDepartures.count, 5)
        XCTAssertEqual(arrivals.arrivalsAndDepartures[0].arrivalDepartureStatus, .arriving)
        XCTAssertEqual(arrivals.arrivalsAndDepartures[1].arrivalDepartureStatus, .departing)

        XCTAssertEqual(arrivals.arrivalsAndDepartures[0].vehicleID, "1_4361")
        XCTAssertEqual(arrivals.arrivalsAndDepartures[1].vehicleID, "1_4361")

        XCTAssertEqual(arrivals.arrivalsAndDepartures[2].arrivalDepartureStatus, .arriving)
        XCTAssertEqual(arrivals.arrivalsAndDepartures[3].arrivalDepartureStatus, .departing)
        XCTAssertEqual(arrivals.arrivalsAndDepartures[4].arrivalDepartureStatus, .arriving)
    }

    func testLoading() async throws {
        let arrivals = try await restAPIService.getArrivalsAndDeparturesForStop(id: campusParkwayStopID, minutesBefore: 5, minutesAfter: 30).entry

        XCTAssertEqual(arrivals.nearbyStopIDs.count, 4)
        XCTAssertEqual(arrivals.situationIDs.count, 0)
        XCTAssertEqual(arrivals.arrivalsAndDepartures.count, 1)

        let arrivalDeparture = try XCTUnwrap(arrivals.arrivalsAndDepartures.first)
        XCTAssertTrue(arrivalDeparture.arrivalEnabled)
        XCTAssertEqual(arrivalDeparture.blockTripSequence, 9)
        XCTAssertTrue(arrivalDeparture.arrivalEnabled)
        XCTAssertEqual(arrivalDeparture.distanceFromStop, 1232.648659247323, accuracy: 0.00000001)
        XCTAssertNil(arrivalDeparture.frequency)

        XCTAssertEqual(arrivalDeparture.lastUpdated, Date(timeIntervalSinceReferenceDate: 562834549), "Expected lastUpdated to be 2018-11-02T06:55:49Z")
        XCTAssertEqual(arrivalDeparture.numberOfStopsAway, 4)
        XCTAssertTrue(arrivalDeparture.predicted)

        XCTAssertEqual(arrivalDeparture.routeID, "1_100447")
        XCTAssertNil(arrivalDeparture.routeLongName)
        XCTAssertEqual(arrivalDeparture.routeShortName, "49")

        XCTAssertEqual(arrivalDeparture.arrivalDepartureDate, Date(timeIntervalSince1970: 1541142156), "Expected arrivalDepartureDate to be 2018-11-02T07:02:36Z")
        XCTAssertEqual(arrivalDeparture.serviceDate, Date(timeIntervalSince1970: 1541055600), "Expected serviceDate to be 2018-11-01T07:00:00Z")
        XCTAssertEqual(arrivalDeparture.situationIDs.count, 0)

        XCTAssertEqual(arrivalDeparture.status, "default")
        XCTAssertEqual(arrivalDeparture.stopID, "1_10914")
        XCTAssertEqual(arrivalDeparture.stopSequence, 3)
        XCTAssertEqual(arrivalDeparture.totalStopsInTrip, 22)
        XCTAssertEqual(arrivalDeparture.tripHeadsign, "Downtown Seattle Broadway")
        XCTAssertEqual(arrivalDeparture.tripID, "1_40984902")
        XCTAssertEqual(arrivalDeparture.vehicleID, "1_4559")

        let tripStatus = try XCTUnwrap(arrivalDeparture.tripStatus)
        XCTAssertEqual(tripStatus.activeTripID, "1_40984840")
        XCTAssertEqual(tripStatus.blockTripSequence, 8)
        XCTAssertEqual(tripStatus.closestStopID, "1_9650")
        XCTAssertEqual(tripStatus.distanceAlongTrip, 10052.41120684016, accuracy: 0.000001)

        XCTAssertEqual(tripStatus.orientation, 90)
        XCTAssertEqual(tripStatus.lastLocationUpdateTime, 1541141749000)
        XCTAssertEqual(tripStatus.lastUpdate, Date(timeIntervalSince1970: 1541141749))

        let lastKnownLocation = try XCTUnwrap(tripStatus.lastKnownLocation)
        XCTAssertEqual(lastKnownLocation.coordinate.latitude, 47.66180419921875, accuracy: 0.000001)
        XCTAssertEqual(lastKnownLocation.coordinate.longitude, -122.31656646728516, accuracy: 0.000001)
    }

    func testLoadingRogueValley() async throws {
        // There are some indications that the data shape from RVTD is different from some other regions.
        // This test is meant to ensure that these different data sources work equally well.

        let arrivals = try await restAPIService.getArrivalsAndDeparturesForStop(id: rvtdStopID, minutesBefore: 5, minutesAfter: 30).entry
        XCTAssertEqual(arrivals.nearbyStopIDs.count, 3)
        XCTAssertEqual(arrivals.situationIDs.count, 0)

        XCTAssertEqual(arrivals.stopID, "1739_d1e8e68e-83f8-487f-baf5-f465fe70fc84")
        XCTAssertEqual(arrivals.arrivalsAndDepartures.count, 1)

        let arrivalDeparture = try XCTUnwrap(arrivals.arrivalsAndDepartures.first)
        XCTAssertTrue(arrivalDeparture.arrivalEnabled)
        XCTAssertEqual(arrivalDeparture.blockTripSequence, 2)
        XCTAssertTrue(arrivalDeparture.departureEnabled)
        XCTAssertEqual(arrivalDeparture.distanceFromStop, 63293.0860, accuracy: 0.0001)
        XCTAssertNil(arrivalDeparture.frequency)
    }
}
