//
//  TripMapHostViewControllerExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKitCore
@testable import OBAKit

/// Extended tests for `TripMapHostViewController` destinationStopID passing,
/// lifecycle initialization, and view controller hierarchy invariants.
@Suite(.serialized)
@MainActor
final class TripMapHostViewControllerExtendedTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    @Test func `Host preserves destinationStopID when provided in designated initializer`() throws {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let departure = try makeDeparture()
        let convertible = TripConvertible(arrivalDeparture: departure)

        let host = TripMapHostViewController(
            application: app,
            tripConvertible: convertible,
            destinationStopID: "1_destination_stop"
        )

        #expect(host.destinationStopID == "1_destination_stop")
        #expect(host.tripPage.destinationStopID == "1_destination_stop")
    }

    @Test func `Host leaves destinationStopID nil by default`() throws {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let departure = try makeDeparture()

        let host = TripMapHostViewController(application: app, arrivalDeparture: departure)

        #expect(host.destinationStopID == nil)
        #expect(host.tripPage.destinationStopID == nil)
    }

    @Test func `Host initializes tripPage with matching application`() throws {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let departure = try makeDeparture()

        let host = TripMapHostViewController(application: app, arrivalDeparture: departure)

        #expect(host.application === app)
        #expect(host.tripPage.application === app)
    }
}
