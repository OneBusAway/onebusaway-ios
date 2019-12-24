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

    func testURLConstruction_tampa() {
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "key", value: "org.onebusaway.iphone"))
        queryItems.append(URLQueryItem(name: "app_uid", value: "F89DB514-24C2-4C33-A25D-876F96C5A59D"))
        queryItems.append(URLQueryItem(name: "app_ver", value: "1.0"))
        queryItems.append(URLQueryItem(name: "version", value: "2"))

        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: "Hillsborough Area Regional Transit_4543", minutesBefore: 5, minutesAfter: 35, baseURL: URL(string: "http://api.tampa.onebusaway.org/api/")!, queryItems: queryItems)

        expect(url.absoluteString) == "http://api.tampa.onebusaway.org/api/api/where/arrivals-and-departures-for-stop/Hillsborough%20Area%20Regional%20Transit_4543.json?minutesAfter=35&minutesBefore=5&key=org.onebusaway.iphone&app_uid=F89DB514-24C2-4C33-A25D-876F96C5A59D&app_ver=1.0&version=2"
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
