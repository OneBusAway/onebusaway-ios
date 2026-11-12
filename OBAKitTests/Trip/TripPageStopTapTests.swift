//
//  TripPageStopTapTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKitCore
@testable import OBAKit

/// Tapping a stop on the trip page, driven through the page's own stop action and
/// read back from the stop screen it pushes: the transfer context is what the
/// stop page highlights the trip from, and what the legacy one draws its arrival
/// banner from.
@Suite(.serialized)
@MainActor
final class TripPageStopTapTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Route 49 to Downtown Seattle Broadway, boarding at stop 1_10914.
    private func makeDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    private func row(index: Int, stopID: StopID, arrival: TimeInterval) -> TripStopListModel.Row {
        TripStopListModel.Row(
            id: "\(index)-\(stopID)",
            stopID: stopID,
            name: "Stop \(index)",
            coordinate: nil,
            date: Date(timeIntervalSince1970: arrival),
            isPassed: false,
            isVehicleHere: false,
            isUserStop: false,
            isTerminal: false
        )
    }

    /// Taps `row` on a page pushed onto a stack, and returns the stop screen it opened.
    private func tap(_ row: TripStopListModel.Row, on page: TripPageViewController) throws -> StopPageViewController {
        let navigation = UINavigationController(rootViewController: page)
        page.rootView.actions.onSelectStop(row)
        #expect(navigation.viewControllers.count == 2)
        return try #require(navigation.viewControllers.last as? StopPageViewController)
    }

    @Test func `A stop after boarding opens with the trip's arrival time there`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let departure = try makeDeparture()
        #expect(departure.stopID == "1_10914")
        let page = TripPageViewController(application: application, arrivalDeparture: departure)

        let stop = try tap(row(index: 6, stopID: "1_10920", arrival: 1_541_142_600), on: page)

        let context = try #require(stop.transferContext)
        #expect(context.arrivalTime == Date(timeIntervalSince1970: 1_541_142_600))
        #expect(context.fromRouteShortName == "49")
        #expect(context.fromTripHeadsign == "Downtown Seattle Broadway")
        #expect(context.fromTripID == "1_40984902")
    }

    @Test func `The boarding stop opens with no transfer context`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = TripPageViewController(application: application, arrivalDeparture: try makeDeparture())

        let stop = try tap(row(index: 3, stopID: "1_10914", arrival: 1_541_142_000), on: page)

        #expect(stop.transferContext == nil)
    }

    /// A trip opened from a vehicle has no departure, so no boarding stop.
    @Test func `A stop on a trip with no departure opens with no transfer context`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        let tripDetails = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data).entry
        let convertible = TripConvertible(tripDetails: tripDetails)
        #expect(convertible.arrivalDeparture == nil)
        let page = TripPageViewController(application: application, tripConvertible: convertible)

        let stop = try tap(row(index: 6, stopID: "1_10920", arrival: 1_541_142_600), on: page)

        #expect(stop.transferContext == nil)
    }

    /// Two rows for one stop, as a loop route that calls at it twice has. The
    /// context takes its time from the row that was tapped, never from another
    /// row for the same stop.
    @Test func `A loop stop opens with the time of the visit that was tapped`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let page = TripPageViewController(application: application, arrivalDeparture: try makeDeparture())
        let firstVisit = row(index: 6, stopID: "1_10920", arrival: 1_541_142_600)
        let secondVisit = row(index: 14, stopID: "1_10920", arrival: 1_541_144_400)
        #expect(firstVisit.stopID == secondVisit.stopID)

        let stop = try tap(secondVisit, on: page)

        #expect(stop.transferContext?.arrivalTime == Date(timeIntervalSince1970: 1_541_144_400))
    }
}
