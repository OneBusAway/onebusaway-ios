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
}
