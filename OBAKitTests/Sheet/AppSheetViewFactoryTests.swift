//
//  AppSheetViewFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import SwiftUI
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Per-route factory branch coverage. Each branch that's been "wired up"
/// (i.e. removed from the shared `unimplementedView` catch-all) gets a
/// dedicated test so a future refactor that accidentally drops the branch
/// back into the catch-all fails the suite.
final class AppSheetViewFactoryTests: OBATestCase {

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
    func test_moreView_returnsMoreSheetHostForwardingApplication() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let host = factory.moreView()

        // Reference identity: the factory must forward its own `Application`
        // into the host, not construct a new one or drop it. `MoreSheetHost`'s
        // wiring itself (produces a UINavigationController wrapping
        // MoreViewController) is covered by MoreSheetHostTests — this test
        // owns the factory-to-host handoff only.
        expect(host.application === application) == true
    }

    @MainActor
    func test_stopDetailView_returnsStopDetailSheetHostForwardingApplicationAndStopID() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let host = factory.stopDetailView(stopID: "1_10914")

        expect(host.application === application) == true
        expect(host.stopID) == "1_10914"
    }
}
