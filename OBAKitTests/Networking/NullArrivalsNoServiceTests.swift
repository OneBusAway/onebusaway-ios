//
//  NullArrivalsNoServiceTests.swift
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

// swiftlint:disable force_cast

/// Java OBA servers before 2.7.2 send an arrivals body of literal `null` both for a
/// stop that doesn't exist and for a stop with no service on the requested day
/// (OneBusAway/maglev#2102). `getArrivalsAndDeparturesForStop` fetches the stop to
/// tell the two apart.
@Suite(.serialized)
final class NullArrivalsNoServiceTests: OBATestCase {
    private let stopID = "1_1121"

    private var dataLoader: MockDataLoader { restService.dataLoader as! MockDataLoader }

    private func stubNullArrivals() {
        dataLoader.mock(data: Data("null".utf8)) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop/") ?? false
        }
    }

    @Test func `A null arrivals body for an existing stop becomes an empty arrivals list`() async throws {
        stubNullArrivals()
        Fixtures.stubStop(dataLoader: dataLoader, data: Fixtures.loadData(file: "stop_1_1121.json"))

        let response = try await restService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: 5, minutesAfter: 30)
        let arrivals = response.entry

        #expect(arrivals.arrivalsAndDepartures.isEmpty)
        #expect(arrivals.id == stopID)
        #expect(arrivals.stop.id == stopID)
        #expect(arrivals.stop.name == "Westlake Station - Bay A")
        #expect(arrivals.nearbyStops.isEmpty)
        #expect(arrivals.serviceAlerts.isEmpty)
        #expect(response.serverClock != nil)
    }

    @Test func `A null arrivals body for a stop the server answers null for is still a missing stop`() async throws {
        stubNullArrivals()
        Fixtures.stubMissingStop(dataLoader: dataLoader)

        await #expect {
            _ = try await self.restService.getArrivalsAndDeparturesForStop(id: self.stopID, minutesBefore: 5, minutesAfter: 30)
        } throws: { error in
            (error as? APIError)?.indicatesMissingStop == true
        }
    }

    @Test func `A null arrivals body for a stop that 404s is still a missing stop`() async throws {
        stubNullArrivals()
        Fixtures.stubStop(dataLoader: dataLoader, data: Data(), statusCode: 404)

        await #expect {
            _ = try await self.restService.getArrivalsAndDeparturesForStop(id: self.stopID, minutesBefore: 5, minutesAfter: 30)
        } throws: { error in
            (error as? APIError)?.indicatesMissingStop == true
        }
    }

    @Test func `A stop lookup that returns HTML is not reported as a missing stop`() async throws {
        stubNullArrivals()
        dataLoader.mock(data: Data("<html><body>Sign in to Wi-Fi</body></html>".utf8), contentType: "text/html") { request in
            request.url?.path.contains("/api/where/stop/") ?? false
        }

        await #expect {
            _ = try await self.restService.getArrivalsAndDeparturesForStop(id: self.stopID, minutesBefore: 5, minutesAfter: 30)
        } throws: { error in
            guard let apiError = error as? APIError else { return false }
            return !apiError.indicatesMissingStop
        }
    }

    @Test func `A failed stop lookup is not reported as a missing stop`() async throws {
        stubNullArrivals()
        Fixtures.stubStop(dataLoader: dataLoader, data: Data(), statusCode: 500)

        await #expect {
            _ = try await self.restService.getArrivalsAndDeparturesForStop(id: self.stopID, minutesBefore: 5, minutesAfter: 30)
        } throws: { error in
            guard let apiError = error as? APIError else { return false }
            return !apiError.indicatesMissingStop
        }
    }
}
