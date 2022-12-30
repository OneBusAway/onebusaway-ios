//
//  TripArrivalsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast function_body_length

class TripArrivalsModelOperationTests: OBATestCase {
    let stopID = "1_10914"
    lazy var apiPath = "https://www.example.com/api/where/arrival-and-departure-for-stop/\(stopID).json"

    func testLoading_success() async throws {
        let dataLoader = (betterRESTService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        dataLoader.mock(URLString: apiPath, with: data)

        let response = try await betterRESTService.getTripArrivalDepartureAtStop(stopID: stopID, tripID: "trip123", serviceDate: Date(timeIntervalSince1970: 1234567890), vehicleID: "vehicle_123", stopSequence: 1)
        let arrDep = response.entry

        expect(arrDep.arrivalEnabled).to(beTrue())
        expect(arrDep.blockTripSequence) == 6
        expect(arrDep.departureEnabled).to(beTrue())
        expect(arrDep.distanceFromStop).to(beCloseTo(-2089.5461))
        expect(arrDep.frequency).to(beNil())

        expect(arrDep.lastUpdated) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 13, second: 42)

        expect(arrDep.numberOfStopsAway) == -4
        expect(arrDep.predicted).to(beTrue())

        expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 10, second: 00)

        expect(arrDep.route.id) == "MTS_10"
        expect(arrDep.route.shortName) == "10"

        expect(arrDep.routeLongName) == "Old Town - University/College"
        expect(arrDep.routeShortName) == "10"

        expect(arrDep.arrivalDepartureDate) == Date.fromComponents(year: 2018, month: 10, day: 24, hour: 03, minute: 10, second: 00)

        expect(arrDep.serviceDate) == Date.fromComponents(year: 2018, month: 10, day: 23, hour: 07, minute: 00, second: 00)

        expect(arrDep.serviceAlerts.count) == 1

        let situation = try XCTUnwrap(arrDep.serviceAlerts.first)
        let situationSummary = try XCTUnwrap(situation.summary)
        let firstConsequence = try XCTUnwrap(situation.consequences.first)

        expect(situationSummary.value) == "Washington St. ramp from Pac Hwy Closed"
        expect(firstConsequence.condition) == "detour"
        expect(firstConsequence.conditionDetails?.diversionPath).toNot(beNil())

        expect(arrDep.status) == "default"

        expect(arrDep.stop.id) == "MTS_11589"
        expect(arrDep.stop.name) == "Pacific Hwy & Sports Arena Bl"

        expect(arrDep.stopSequence) == 1

        expect(arrDep.totalStopsInTrip).to(beNil())

        expect(arrDep.tripHeadsign) == "University & College"

        expect(arrDep.trip.id) == "MTS_13405160"
        expect(arrDep.trip.shortName).to(beNil())

        expect(arrDep.tripStatus).toNot(beNil())
        let tripStatus = try XCTUnwrap(arrDep.tripStatus)
        expect(tripStatus.activeTrip.id) == "MTS_13405160"

        expect(arrDep.vehicleID) == "MTS_806"

    }
}
