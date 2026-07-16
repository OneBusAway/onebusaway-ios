//
//  MoreSheetHostTests.swift
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

/// Smoke-tests for the UIKit wiring wrapper around `MoreViewController`.
/// The wrapping is the entire product surface of `MoreSheetHost`, so these
/// tests drive the representable through its `internal`
/// `makeNavigationController(application:)` factory seam and inspect the
/// resulting controller hierarchy — no `UIHostingController` needed.
final class MoreSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_makeNavigationController_wrapsMoreViewControllerInNav() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let nav = MoreSheetHost.makeNavigationController(application: application)

        expect(nav.viewControllers.count) == 1
        expect(nav.topViewController).to(beAKindOf(MoreViewController.self))
    }
}
