//
//  StopDetailSheetHostTests.swift
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

@Suite(.serialized)
final class StopDetailSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `Make navigation controller wraps the stop page controller in a nav`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914", onClose: {})

        #expect(nav.viewControllers.count == 1)
        #expect(nav.topViewController is StopPageViewController)
    }

    /// The host installs a leading Close button so the stacked stop-detail sheet
    /// can be dismissed without dragging it down.
    @Test func `Make navigation controller installs a leading close button`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = StopDetailSheetHost.makeNavigationController(application: application, stopID: "1_10914", onClose: {})

        let closeButton = nav.topViewController?.navigationItem.leftBarButtonItem
        #expect(closeButton != nil)
        #expect(closeButton?.title == Strings.close)
    }
}
