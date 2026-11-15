//
//  StopArrivalsExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopArrivalsExtendedTests: OBATestCase {

    private let fixtureFile = "arrivals-and-departures_1_1121.json"

    @Test func `StopArrivals decodes and maps stop and arrivals references`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile)

        #expect(stopArrivals.stopID == "1_1121")
        #expect(stopArrivals.id == "1_1121")
        #expect(stopArrivals.stop != nil)
        #expect(stopArrivals.stop.id == "1_1121")
        #expect(!stopArrivals.arrivalsAndDepartures.isEmpty)
    }

    @Test func `StopArrivals deduplicates serviceAlerts across arrivalsAndDepartures`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile)

        let alerts = stopArrivals.serviceAlerts
        var seenIDs = Set<String>()
        for alert in alerts {
            #expect(!seenIDs.contains(alert.id))
            seenIDs.insert(alert.id)
        }
    }

    @Test func `StopArrivals nearbyStops resolves from references`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile)
        #expect(!stopArrivals.nearbyStopIDs.isEmpty)
        #expect(stopArrivals.nearbyStops.count == stopArrivals.nearbyStopIDs.count)
    }

    @Test func `Ingestion pipeline automatically filters implausible epoch dates`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile)
        for ad in stopArrivals.arrivalsAndDepartures {
            #expect(ad.hasPlausibleArrivalDepartureDate)
            #expect(ad.arrivalDepartureDate >= ArrivalDeparture.earliestPlausibleDate)
        }
    }
}
