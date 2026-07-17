//
//  StopDetailSheetHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class StopDetailSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_makeNavigationController_wrapsStopViewControllerInNav() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914")

        expect(nav.viewControllers.count) == 1
        expect(nav.topViewController).to(beAKindOf(StopViewController.self))
    }
}
