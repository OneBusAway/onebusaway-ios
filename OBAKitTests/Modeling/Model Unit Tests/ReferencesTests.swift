//
//  ReferencesTests.swift
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

// swiftlint:disable force_try

class ReferencesTests: OBATestCase {
    var references: References!

    let tampaRegionIdentifier = 0

    override func setUp() {
        super.setUp()
        let data = Fixtures.loadData(file: "references.json")
        references = try! JSONDecoder.RESTDecoder(regionIdentifier: tampaRegionIdentifier).decode(References.self, from: data)
    }

    // MARK: - Agencies

    func test_agencies_success() {
        let agencies = references.agencies

        expect(agencies.count) == 1

        let agency = agencies.first!
        expect(agency.disclaimer).to(beNil())
        expect(agency.id) == "Hillsborough Area Regional Transit"
        expect(agency.language) == "en"
        expect(agency.name) == "Hillsborough Area Regional Transit"
        expect(agency.phone) == "813-254-4278"
        expect(agency.isPrivateService).to(beFalse())
        expect(agency.timeZone) == "America/New_York"
        expect(agency.agencyURL) == URL(string: "http://www.gohart.org")!
    }

    // MARK: - Routes

    func test_routes_success() {
        // Make sure routes are being sorted by their IDs for binary searching.
        let expectedRoutes = ["Hillsborough Area Regional Transit_1", "Hillsborough Area Regional Transit_12", "Hillsborough Area Regional Transit_14", "Hillsborough Area Regional Transit_16", "Hillsborough Area Regional Transit_18", "Hillsborough Area Regional Transit_2", "Hillsborough Area Regional Transit_21", "Hillsborough Area Regional Transit_33", "Hillsborough Area Regional Transit_39", "Hillsborough Area Regional Transit_400", "Hillsborough Area Regional Transit_41", "Hillsborough Area Regional Transit_45", "Hillsborough Area Regional Transit_5", "Hillsborough Area Regional Transit_57", "Hillsborough Area Regional Transit_6", "Hillsborough Area Regional Transit_9"]

        expect(self.references.routes.map { $0.id }).to(equal(expectedRoutes), description: "Make sure routes are sorted by their IDs for binary searching")

        let route = self.references.routes.first!
        expect(route.agencyID) == "Hillsborough Area Regional Transit"
        expect(route.agency.name) == "Hillsborough Area Regional Transit"
        expect(route.color).to(beCloseTo(UIColor(red: (9.0 / 255.0), green: (52.0 / 255.0), blue: (109.0 / 255.0), alpha: 1.0)))
        expect(route.routeDescription).to(beNil())
        expect(route.id) == "Hillsborough Area Regional Transit_1"
        expect(route.longName) == "Florida Avenue"
        expect(route.shortName) == "1"
        expect(route.textColor).to(beCloseTo(UIColor.white))
        expect(route.routeType) == .bus
        expect(route.routeURL) == URL(string: "http://www.gohart.org/routes/hart/01.html")!
        expect(route.regionIdentifier) == 0
    }

    // MARK: - Service Alerts

    func test_serviceAlerts_success() {
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try! JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        let situations = response.references!.serviceAlerts

        expect(situations.count) == 1

        let situation = situations.first!

        let activeWindow = situation.activeWindows.first!
        expect(activeWindow.interval) == DateInterval(start: Date(timeIntervalSince1970: 1539781200),
                                                      end: Date(timeIntervalSince1970: 1539826200))

        let entity = situation.affectedEntities.first!
        expect(entity.routeID) == "MTS_10"

        let consequence = situation.consequences.first!
        expect(consequence.condition) == "detour"
        expect(consequence.conditionDetails!.diversionPath) == "ue}aHt~hiVYxHt@lIxAjD|`@pb@tDbHh@|EHvEU~l@fAfN`C~E|DvDbIvB|NdClMxCbEbA`CxDfB`FLrKsNl]gA{@gPGKjF"
        expect(consequence.conditionDetails?.stopIDs) == ["1_9972", "1_9974"]

        expect(situation.createdAt) == Date.fromComponents(year: 2018, month: 10, day: 13, hour: 02, minute: 26, second: 33)

        let desc = situation.situationDescription
        expect(desc?.lang) == "en"
        expect(desc?.value) == "Due to construction, the Washington St. off ramp from Pacific Highway will be closed Wednesday, October 17, from 6:30am - 6:30pm. Eastbound route 10 will detour, but will not miss any stops."

        expect(situation.id) == "MTS_RTA:11638227"
        expect(situation.publicationWindows) == []
        expect(situation.reason) == "CONSTRUCTION"
        expect(situation.severity) == ""
        expect(situation.summary!.lang) == "en"
        expect(situation.summary!.value) == "Washington St. ramp from Pac Hwy Closed"
        expect(situation.urlString).to(beNil())
    }

    // MARK: - Stops

    func test_stops_success() {
        // Make sure stops are being sorted by their IDs for binary searching.
        let expectedOrder = ["Hillsborough Area Regional Transit_1513", "Hillsborough Area Regional Transit_2601", "Hillsborough Area Regional Transit_2625", "Hillsborough Area Regional Transit_3113", "Hillsborough Area Regional Transit_3114", "Hillsborough Area Regional Transit_3432", "Hillsborough Area Regional Transit_4301", "Hillsborough Area Regional Transit_4493", "Hillsborough Area Regional Transit_454", "Hillsborough Area Regional Transit_4547", "Hillsborough Area Regional Transit_455", "Hillsborough Area Regional Transit_4604", "Hillsborough Area Regional Transit_4677", "Hillsborough Area Regional Transit_6497", "Hillsborough Area Regional Transit_6499", "Hillsborough Area Regional Transit_6528", "Hillsborough Area Regional Transit_6592", "Hillsborough Area Regional Transit_683", "Hillsborough Area Regional Transit_6902", "Hillsborough Area Regional Transit_698", "Hillsborough Area Regional Transit_6990", "Hillsborough Area Regional Transit_7434", "Hillsborough Area Regional Transit_7581", "Hillsborough Area Regional Transit_7703", "Hillsborough Area Regional Transit_7924", "Hillsborough Area Regional Transit_928"]

        expect(self.references.stops.map { $0.id }).to(equal(expectedOrder), description: "Make sure stops are sorted by their IDs for binary searching")

        guard let stop = self.references.stopWithID("Hillsborough Area Regional Transit_6497") else {
            fail("Failed to find stop with stopID: \"Hillsborough Area Regional Transit_6497\"")
            return
        }

        expect(stop.code) == "6497"
        expect(stop.direction) == .unknown
        expect(stop.id) == "Hillsborough Area Regional Transit_6497"
        expect(stop.location.coordinate.latitude).to(beCloseTo(28.066419, within: 0.01))
        expect(stop.location.coordinate.longitude).to(beCloseTo(-82.429872, within: 0.01))
        expect(stop.locationType) == .stop
        expect(stop.name) == "University Area Transit Center"
        expect(stop.routeIDs.count) == 10
        expect(stop.routeIDs.first!) == "Hillsborough Area Regional Transit_1"
        expect(stop.routes.first!.shortName) == "1"
        expect(stop.wheelchairBoarding) == .unknown
    }

    // MARK: - Trips

    func test_trips_success() {
        // Make sure stops are being sorted by their IDs for binary searching.
        let expectedTrips = ["Hillsborough Area Regional Transit_101412", "Hillsborough Area Regional Transit_101445", "Hillsborough Area Regional Transit_102332", "Hillsborough Area Regional Transit_102333", "Hillsborough Area Regional Transit_102381", "Hillsborough Area Regional Transit_102382", "Hillsborough Area Regional Transit_102675", "Hillsborough Area Regional Transit_102676", "Hillsborough Area Regional Transit_102677", "Hillsborough Area Regional Transit_98479", "Hillsborough Area Regional Transit_98522", "Hillsborough Area Regional Transit_98523", "Hillsborough Area Regional Transit_98683", "Hillsborough Area Regional Transit_98684", "Hillsborough Area Regional Transit_98715", "Hillsborough Area Regional Transit_98716", "Hillsborough Area Regional Transit_98870", "Hillsborough Area Regional Transit_98902", "Hillsborough Area Regional Transit_99282", "Hillsborough Area Regional Transit_99283", "Hillsborough Area Regional Transit_99312", "Hillsborough Area Regional Transit_99313", "Hillsborough Area Regional Transit_99494", "Hillsborough Area Regional Transit_99495", "Hillsborough Area Regional Transit_99538", "Hillsborough Area Regional Transit_99539", "Hillsborough Area Regional Transit_99872", "Hillsborough Area Regional Transit_99873", "Hillsborough Area Regional Transit_99904", "Hillsborough Area Regional Transit_99905"]

        expect(self.references.trips.map { $0.id }).to(equal(expectedTrips), description: "Make sure trips are sorted by their IDs for binary searching")

        guard let trip = self.references.tripWithID("Hillsborough Area Regional Transit_99283") else {
            fail("Failed to find trip with tripID: \"Hillsborough Area Regional Transit_99283\"")
            return
        }

        expect(trip.blockID) == "Hillsborough Area Regional Transit_288317"
        expect(trip.direction).to(beNil())
        expect(trip.id) == "Hillsborough Area Regional Transit_99283"
        expect(trip.routeID) == "Hillsborough Area Regional Transit_9"
        expect(trip.route.shortName) == "9"
        expect(trip.routeShortName).to(beNil())
        expect(trip.shortName).to(beNil())
        expect(trip.serviceID) == "Hillsborough Area Regional Transit_We"
        expect(trip.timeZone).to(beNil())
        expect(trip.shapeID) == "Hillsborough Area Regional Transit_38042"
        expect(trip.headsign) == "Downtown to UATC via 15th St"
    }
}
