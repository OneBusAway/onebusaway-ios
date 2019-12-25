//
//  StopArrivalsAndDeparturesOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class StopArrivalsAndDeparturesOperationTest: OBATestCase {
    func testAPIPath() {
        expect(StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: "Hello/World")) == "/api/where/arrivals-and-departures-for-stop/Hello%2FWorld.json"
    }

    func testURLConstruction_absurd() {
        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: "Here is a ridiculous string!/But not impossible to see in OBA's data :-\\", minutesBefore: 5, minutesAfter: 35, baseURL: URL(string: "http://api.tampa.onebusaway.org/api/")!, queryItems: [URLQueryItem]())

        expect(url.absoluteString.components(separatedBy: "?").first!) == "http://api.tampa.onebusaway.org/api/api/where/arrivals-and-departures-for-stop/Here%20is%20a%20ridiculous%20string!%2FBut%20not%20impossible%20to%20see%20in%20OBA's%20data%20:-%5C.json"
    }

    func testURLConstruction_tampa() {
        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: "Hillsborough Area Regional Transit_4543", minutesBefore: 5, minutesAfter: 35, baseURL: URL(string: "http://api.tampa.onebusaway.org/api/")!, queryItems: [URLQueryItem]())

        expect(url.absoluteString.components(separatedBy: "?").first!) == "http://api.tampa.onebusaway.org/api/api/where/arrivals-and-departures-for-stop/Hillsborough%20Area%20Regional%20Transit_4543.json"
    }

    func testSuccessfulStopsForRouteRequest() {
        // http://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_75414.json?key=TEST&minutesBefore=5&minutesAfter=10
        let stopID = "1_75414"
        let minutesBefore = "5"
        let minutesAfter = "10"

        let expectedParams = [
            "minutesBefore": minutesBefore,
            "minutesAfter": minutesAfter
        ]

        let apiPath = StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: stopID)

        stub(condition: isHost(self.host) &&
            isPath(apiPath) &&
            containsQueryParams(expectedParams)
        ) { _ in
            return OHHTTPStubsResponse.JSONFile(named: "arrivals-and-departures-for-stop-1_75414.json")
        }

        waitUntil { done in
            let op = self.restService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: 5, minutesAfter: 10)
            op.completionBlock = {
                let entries = op.entries!
                expect(entries.count) == 1
                let entry = entries.first!
                expect((entry["arrivalsAndDepartures"] as! [Any]).count) == 1

                let references = op.references!
                let stops = references["stops"] as! [Any]
                expect(stops.count) == 4

                done()
            }
        }
    }
}
