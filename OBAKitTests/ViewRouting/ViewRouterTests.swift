//
//  ViewRouterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
import OBAKitCore

@Suite(.serialized)
@MainActor
final class ViewRouterTests: OBATestCase {

    @Test func `Navigate to StopID pushes a stop controller`() throws {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        application.viewRouter.navigateTo(stopID: "1_123", from: root)

        let pushed = try #require(navigation.viewControllers.last)
        #expect(pushed !== root, "Expected a new view controller to be pushed")

        let isStopController = pushed is StopViewController || pushed is StopPageViewController
        #expect(isStopController, "Expected pushed controller to be a stop controller")
    }

    /// Both stop screens, because each draws the context its own way: the new
    /// page highlights the trip, the legacy one shows the arrival banner.
    @Test(arguments: [true, false])
    func `Navigate to StopID hands the transfer context to the stop screen`(newStopPage: Bool) throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        application.userDefaults.set(newStopPage, forKey: FeatureFlags.useNewStopPageKey)
        #expect(application.userDataStore.showTransferArrivalBanner)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_700_000_000),
            fromRouteShortName: "49",
            fromTripHeadsign: "Downtown Seattle Broadway",
            fromTripID: "1_40984902"
        )

        application.viewRouter.navigateTo(stopID: "1_123", from: root, transferContext: context)

        let pushed = try #require(navigation.viewControllers.last as? StopContextConfigurable)
        #expect((pushed is StopPageViewController) == newStopPage)
        #expect(pushed.transferContext == context)
    }

    @Test func `Navigate to StopID drops the transfer context when the transfer banner is off`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        application.userDataStore.showTransferArrivalBanner = false

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_700_000_000),
            fromRouteShortName: "49",
            fromTripHeadsign: "Downtown Seattle Broadway"
        )

        application.viewRouter.navigateTo(stopID: "1_123", from: root, transferContext: context)

        let pushed = try #require(navigation.viewControllers.last as? StopContextConfigurable)
        #expect(pushed.transferContext == nil)
    }

    /// A shared trip link: boarding at 1_75414 (row 5 of trip 1_18196913), the
    /// sharer stepping off at 1_25900 (row 20). The destination has to reach the
    /// stops the rider sees, in the list and on the map, not just be stored.
    @Test func `Navigate to arrivalDeparture pushes the trip map host, and a shared destination reaches its stop list and map`() async throws {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        let trip = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/trip-details") ?? false }
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/arrival-and-departure-for-stop") ?? false }
        let emptyShape = Data(#"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.utf8)
        dataLoader.mock(data: emptyShape) { $0.url?.path.contains("/api/where/shape") ?? false }
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        // Loaded with its references, which the page reads as soon as its view
        // loads. Its own trip differs, but the stop list is built from the trip
        // details the stub answers with, where 1_75414 is row 5.
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let boarding = try #require(stopArrivals.arrivalsAndDepartures.first)
        #expect(boarding.stopID == "1_75414")
        application.viewRouter.navigateTo(arrivalDeparture: boarding, from: root, destinationStopID: "1_25900")

        let host = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        host.loadViewIfNeeded()
        host.tripPage.viewModel.loadData()
        await host.tripPage.viewModel.loadDataTask?.value

        let list = host.tripPage.viewModel.stopList
        #expect(list.rows.count == 53)
        #expect(list.rows.firstIndex { $0.isUserStop } == 20)
        #expect(list.rows[20].stopID == "1_25900")
        #expect(list.rows.firstIndex { $0.isBoardingStop } == 5)

        let mapStops = try #require(host.tripPage.mapFocus.content?.stops)
        #expect(mapStops.firstIndex { $0.isUserStop } == 20)
        #expect(mapStops.firstIndex { $0.isBoardingStop } == 5)
    }
}
