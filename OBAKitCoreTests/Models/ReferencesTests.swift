//
//  ReferencesTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

final class ReferencesTests: OBAKitCoreTestCase {
    private let stopID_hart_6497 = "Hillsborough Area Regional Transit_6497"
    private let stopID_MTS_11589 = "MTS_11589"

    override func setUp() async throws {
        try await super.setUp()

        dataLoader.mock(
            URLString: "https://www.example.com/api/where/arrivals-and-departures-for-stop/\(stopID_hart_6497).json",
            with: try Fixtures.loadData(file: "arrivals_and_departures_for_stop_hart_6497.json")
        )

        dataLoader.mock(
            URLString: "https://www.example.com/api/where/arrival-and-departure-for-stop/\(stopID_MTS_11589).json",
            with: try Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        )
    }
    
    func testAgencies() async throws {
        let response = try await restAPIService.getArrivalsAndDeparturesForStop(id: stopID_hart_6497, minutesBefore: 0, minutesAfter: 60)
        let references = try XCTUnwrap(response.references)

        let agencies = references.agencies
        XCTAssertEqual(agencies.count, 1)

        let agency = try XCTUnwrap(agencies.first)
        XCTAssertNil(agency.disclaimer)
        XCTAssertEqual(agency.id, "Hillsborough Area Regional Transit")
        XCTAssertEqual(agency.language, "en")
        XCTAssertEqual(agency.name, "Hillsborough Area Regional Transit")
        XCTAssertEqual(agency.phone, "813-254-4278")
        XCTAssertFalse(agency.isPrivateService)
        XCTAssertEqual(agency.timeZone, "America/New_York")
        XCTAssertEqual(agency.agencyURL.absoluteString, "http://www.gohart.org")
    }

    func testRoutes() async throws {
        let response = try await restAPIService.getArrivalsAndDeparturesForStop(id: stopID_hart_6497, minutesBefore: 0, minutesAfter: 60)
        let references = try XCTUnwrap(response.references)

        let routes = references.routes
        XCTAssertEqual(routes.count, 16)

        let route = try XCTUnwrap(routes.first)
        XCTAssertEqual(route.id, "Hillsborough Area Regional Transit_1")
        XCTAssertEqual(route.longName, "Florida Avenue")
        XCTAssertEqual(route.shortName, "1")
        XCTAssertNil(route.routeDescription)
        XCTAssertEqual(route.routeType, .bus)
        XCTAssertEqual(route.routeURL?.absoluteString, "http://www.gohart.org/routes/hart/01.html")
        XCTAssertEqual(route.agencyID, "Hillsborough Area Regional Transit")
        XCTAssertEqual(route.textColor, UIColor(red: 1, green: 1, blue: 1, alpha: 1), "Expected route.textColor to be equal to White (RGB color space).")
        XCTAssertEqual(route.color, UIColor(
            red: (9.0 / 255.0),
            green: (52.0 / 255.0),
            blue: (109.0 / 255.0),
            alpha: 1.0)
        )
    }

    func testSituations() async throws {
        let response = try await restAPIService.getTripArrivalDepartureAtStop(stopID: stopID_MTS_11589, tripID: "MTS_13405160", serviceDate: Date(timeIntervalSince1970: 0), vehicleID: nil, stopSequence: 0)
        //        let response = try await restAPIService.getArrivalsAndDeparturesForStop(id: stopID_MTS_11589, minutesBefore: 0, minutesAfter: 60)
        let references = try XCTUnwrap(response.references)

        let situations = references.situations
        XCTAssertEqual(situations.count, 1)

        let situation = try XCTUnwrap(situations.first)
        XCTAssertEqual(situation.creationTime,  Date(timeIntervalSince1970: 1539397593))
        XCTAssertEqual(situation.description?.lang, "en")
        XCTAssertEqual(situation.description?.value, "Due to construction, the Washington St. off ramp from Pacific Highway will be closed Wednesday, October 17, from 6:30am - 6:30pm. Eastbound route 10 will detour, but will not miss any stops.")

        XCTAssertEqual(situation.id, "MTS_RTA:11638227")
        XCTAssertTrue(situation.publicationWindows.isEmpty)
        XCTAssertEqual(situation.reason, "CONSTRUCTION")
        XCTAssertEqual(situation.severity, "")
        XCTAssertEqual(situation.summary?.lang, "en")
        XCTAssertEqual(situation.summary?.value, "Washington St. ramp from Pac Hwy Closed")
        XCTAssertNil(situation.url)

        let activeWindow = try XCTUnwrap(situation.activeWindows.first)

        XCTAssertEqual(activeWindow.from, Date(timeIntervalSince1970: 1539781200))
        XCTAssertEqual(activeWindow.to, Date(timeIntervalSince1970: 1539826200))

        let affectedEntity = try XCTUnwrap(situation.allAffects.first)
        XCTAssertNil(affectedEntity.agencyID)           // Test nullifyEmptyString.
        XCTAssertNil(affectedEntity.applicationID)
        XCTAssertNil(affectedEntity.directionID)
        XCTAssertNil(affectedEntity.stopID)
        XCTAssertNil(affectedEntity.tripID)
        XCTAssertEqual(affectedEntity.routeID, "MTS_10")

        let consequence = try XCTUnwrap(situation.consequences.first)
        XCTAssertEqual(consequence.condition, "detour")
        XCTAssertEqual(consequence.conditionDetails?.diversionPath.points, "ue}aHt~hiVYxHt@lIxAjD|`@pb@tDbHh@|EHvEU~l@fAfN`C~E|DvDbIvB|NdClMxCbEbA`CxDfB`FLrKsNl]gA{@gPGKjF")
        XCTAssertEqual(consequence.conditionDetails?.diversionStopIDs, ["1_9972", "1_9974"])
    }

    func testStops() async throws {
        let response = try await restAPIService.getArrivalsAndDeparturesForStop(id: stopID_hart_6497, minutesBefore: 0, minutesAfter: 60)
        let references = try XCTUnwrap(response.references)

        XCTAssertEqual(references.stops.count, 26)

        let _stop = references.stops.first(where: { $0.id == "Hillsborough Area Regional Transit_6497" })
        let stop = try XCTUnwrap(_stop)

        XCTAssertEqual(stop.code, "6497")
        XCTAssertEqual(stop.direction, .unknown)
        XCTAssertEqual(stop.id, "Hillsborough Area Regional Transit_6497")
        XCTAssertEqual(stop.location.coordinate.latitude, 28.066419, accuracy: 0.0001)
        XCTAssertEqual(stop.location.coordinate.longitude, -82.429872, accuracy: 0.0001)
        XCTAssertEqual(stop.locationType, .stop)
        XCTAssertEqual(stop.name, "University Area Transit Center")
        XCTAssertEqual(stop.routeIDs.count, 10)
        XCTAssertEqual(stop.wheelchairBoarding, .unknown)
    }

    func testTrips() async throws {
        let response = try await restAPIService.getArrivalsAndDeparturesForStop(id: stopID_hart_6497, minutesBefore: 0, minutesAfter: 60)
        let references = try XCTUnwrap(response.references)

        XCTAssertEqual(references.trips.count, 30)

        let _trip = references.trips.first(where: { $0.id == "Hillsborough Area Regional Transit_99283" })
        let trip = try XCTUnwrap(_trip)

        XCTAssertEqual(trip.id, "Hillsborough Area Regional Transit_99283")
        XCTAssertEqual(trip.blockID, "Hillsborough Area Regional Transit_288317")
        XCTAssertNil(trip.direction)
        XCTAssertEqual(trip.routeID, "Hillsborough Area Regional Transit_9")
        XCTAssertNil(trip.routeShortName)
        XCTAssertNil(trip.shortName)
        XCTAssertEqual(trip.serviceID, "Hillsborough Area Regional Transit_We")
        XCTAssertNil(trip.timeZone)
        XCTAssertEqual(trip.shapeID, "Hillsborough Area Regional Transit_38042")
        XCTAssertEqual(trip.headsign, "Downtown to UATC via 15th St")
    }
}
