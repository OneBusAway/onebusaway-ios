//
//  ReferencesTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBANetworkingKit

class ReferencesTests: OBATestCase {
    var references: References!
    override func setUp() {
        super.setUp()
        let json = loadJSONDictionary(file: "references.json")
        let refsDictionary = json["references"] as! [String: Any]

        references = try! References.decodeReferences(refsDictionary)
    }
}

// MARK: - Agencies
extension ReferencesTests {
    func test_agencies_success() {
        let agencies = self.references!.agencies

        expect(agencies.count) == 1

        let agency = agencies.first!
        expect(agency.disclaimer) == ""
        expect(agency.id) == "Hillsborough Area Regional Transit"
        expect(agency.language) == "en"
        expect(agency.name) == "Hillsborough Area Regional Transit"
        expect(agency.phone) == "813-254-4278"
        expect(agency.isPrivateService).to(beFalse())
        expect(agency.timeZone) == "America/New_York"
        expect(agency.agencyURL) == URL(string: "http://www.gohart.org")!
    }
}

// MARK: - Routes
extension ReferencesTests {
    func test_routes_success() {
        let routes = self.references!.routes
        expect(routes.count) == 16

        let route = routes.first!
        expect(route.agencyID) == "Hillsborough Area Regional Transit"
        expect(route.color) == "09346D"
        expect(route.routeDescription) == ""
        expect(route.id) == "Hillsborough Area Regional Transit_1"
        expect(route.longName) == "Florida Avenue"
        expect(route.shortName) == "1"
        expect(route.textColor) == "FFFFFF"
        expect(route.routeType) == .bus
        expect(route.routeURL) == URL(string: "http://www.gohart.org/routes/hart/01.html")!
    }
}

// MARK: - Situations
extension ReferencesTests {
    func test_situations_success() {
        let references = self.references!
        let situations = references.situations

        // ABXOXO - todo!
    }
}

// MARK: - Stops
extension ReferencesTests {
    func test_stops_success() {
        let references = self.references!
        let stops = references.stops

        // ABXOXO - todo!
    }
}

// MARK: - Trips
extension ReferencesTests {
    func test_trips_success() {
        let references = self.references!
        let trips = references.trips

        // ABXOXO - todo!
    }
}
