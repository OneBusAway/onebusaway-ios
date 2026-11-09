//
//  ViewRouterExtendedNavigationTests.swift
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
final class ViewRouterExtendedNavigationTests: OBATestCase {

    // MARK: - Navigation with UIViewController Context

    @Test func `Navigate to stopID resolves root controller and pushes properly`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterExtendedNavigationTests"))
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        application.viewRouter.navigateTo(stopID: "1_200", from: root)

        let pushed = try #require(navigation.viewControllers.last)
        #expect(pushed !== root)
    }

    // MARK: - Navigation with Destination Stop

    @Test func `Navigate to arrivalDeparture with matching destination attaches destinationStopID`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterExtendedNavigationTests"))
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        let arrivalDeparture = try Fixtures.arrivalDeparture()
        application.viewRouter.navigateTo(
            arrivalDeparture: arrivalDeparture,
            from: root,
            destinationStopID: "1_80085"
        )

        let pushed = try #require(navigation.viewControllers.last as? TripViewController)
        #expect(pushed.destinationStopID == "1_80085")
    }

    // MARK: - Navigation with Nil Destination Stop

    @Test func `Navigate to arrivalDeparture with nil destination retains nil destinationStopID`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterExtendedNavigationTests"))
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        let arrivalDeparture = try Fixtures.arrivalDeparture()
        application.viewRouter.navigateTo(
            arrivalDeparture: arrivalDeparture,
            from: root,
            destinationStopID: nil
        )

        let pushed = try #require(navigation.viewControllers.last as? TripViewController)
        #expect(pushed.destinationStopID == nil)
    }

    // MARK: - Navigation Destination Enum Equality

    @Test func `NavigationDestination cases preserve payloads`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture()
        let dest = ViewRouter.NavigationDestination.arrivalDeparture(arrivalDeparture)

        switch dest {
        case .arrivalDeparture(let arrDep):
            #expect(arrDep.tripID == arrivalDeparture.tripID)
        default:
            Issue.record("Expected arrivalDeparture case")
        }

        let stopDest = ViewRouter.NavigationDestination.stopID("1_4444")
        switch stopDest {
        case .stopID(let id):
            #expect(id == "1_4444")
        default:
            Issue.record("Expected stopID case")
        }
    }
}
