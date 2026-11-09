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

    @Test func `Navigate to arrivalDeparture pushes TripViewController with destinationStopID`() throws {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        let arrivalDeparture = try Fixtures.arrivalDeparture()
        application.viewRouter.navigateTo(
            arrivalDeparture: arrivalDeparture,
            from: root,
            destinationStopID: "1_999"
        )

        let pushed = try #require(navigation.viewControllers.last)
        #expect(pushed !== root, "Expected a new view controller to be pushed")
        let tripVC = try #require(pushed as? TripViewController, "Expected pushed controller to be TripViewController")
        #expect(tripVC.destinationStopID == "1_999")
    }
}
