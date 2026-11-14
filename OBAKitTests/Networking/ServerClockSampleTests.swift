//
//  ServerClockSampleTests.swift
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

/// A REST response says what time the server thought it was. Vehicle position
/// estimation compares that with the device clock to correct for skew, so a cached
/// response must count the time it spent in the cache (`Age`).
@Suite(.serialized)
final class ServerClockSampleTests: OBATestCase {
    let tripID = "1_18196913"
    lazy var tripDetailsURL = URL(string: "https://www.example.com/api/where/trip-details/\(tripID).json")!

    /// `currentTime` in `trip_details_1_18196913.json`.
    let fixtureServerTime = Date(timeIntervalSince1970: 1343587067.230)

    var dataLoader: MockDataLoader { restService.dataLoader as! MockDataLoader }

    @Test func `A fresh response samples the envelope's current time`() async throws {
        dataLoader.mock(url: tripDetailsURL, with: Fixtures.loadData(file: "trip_details_1_18196913.json"))
        let before = Date()

        let response = try await restService.getTrip(tripID: tripID, vehicleID: nil, serviceDate: nil)

        let sample = try #require(response.serverClock)
        #expect(abs(sample.serverTime.timeIntervalSince(fixtureServerTime)) < 0.001)
        #expect(sample.receivedAt >= before)
        #expect(sample.receivedAt <= Date())
    }

    @Test func `A cached response's server time is advanced by its Age`() async throws {
        dataLoader.mock(url: tripDetailsURL, with: Fixtures.loadData(file: "trip_details_1_18196913.json"), headers: ["Age": "12"])

        let response = try await restService.getTrip(tripID: tripID, vehicleID: nil, serviceDate: nil)

        let sample = try #require(response.serverClock)
        #expect(abs(sample.serverTime.timeIntervalSince(fixtureServerTime) - 12) < 0.001)
    }

    @Test func `A malformed Age is ignored`() async throws {
        dataLoader.mock(url: tripDetailsURL, with: Fixtures.loadData(file: "trip_details_1_18196913.json"), headers: ["Age": "soon"])

        let response = try await restService.getTrip(tripID: tripID, vehicleID: nil, serviceDate: nil)

        let sample = try #require(response.serverClock)
        #expect(abs(sample.serverTime.timeIntervalSince(fixtureServerTime)) < 0.001)
    }

    @Test func `Requests use the protocol cache policy unless told otherwise`() async throws {
        dataLoader.mock(url: tripDetailsURL, with: Fixtures.loadData(file: "trip_details_1_18196913.json"))

        _ = try await restService.getTrip(tripID: tripID, vehicleID: nil, serviceDate: nil)
        _ = try await restService.getTrip(tripID: tripID, vehicleID: nil, serviceDate: nil, cachePolicy: .reloadIgnoringLocalCacheData)

        let policies = dataLoader.recordedRequests.filter { $0.url?.path == tripDetailsURL.path }.map(\.cachePolicy)
        #expect(policies == [.useProtocolCachePolicy, .reloadIgnoringLocalCacheData])
    }
}
