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
    func test_makeNavigationController_wrapsStopPageControllerInNav() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914", onClose: {})

        expect(nav.viewControllers.count) == 1
        expect(nav.topViewController).to(beAKindOf(StopPageViewController.self))
    }

    /// The host installs a leading Close button so the stacked stop-detail sheet
    /// can be dismissed without dragging it down.
    @MainActor
    func test_makeNavigationController_installsLeadingCloseButton() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914", onClose: {})

        let closeButton = nav.topViewController?.navigationItem.leftBarButtonItem
        expect(closeButton).toNot(beNil())
        expect(closeButton?.title) == Strings.close
    }
}
