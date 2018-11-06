//
//  StopArrivalsAndDeparturesOperationTest.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBANetworkingKit

class StopArrivalsAndDeparturesOperationTest: OBATestCase {
    func testAPIPath() {
        expect(StopArrivalsAndDeparturesOperation.buildAPIPath(stopID: "Hello/World")) == "/api/where/arrivals-and-departures-for-stop/Hello%2FWorld.json"
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
            return self.JSONFile(named: "arrivals-and-departures-for-stop-1_75414.json")
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
