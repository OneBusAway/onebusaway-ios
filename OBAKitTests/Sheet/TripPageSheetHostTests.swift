//
//  TripPageSheetHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKitCore
@testable import OBAKit

/// The wiring of the map panel's trip sheet, driven through the representable's
/// `makeTripPage` seam, as `MoreSheetHostTests` does for its host.
@Suite(.serialized)
final class TripPageSheetHostTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test @MainActor
    func `Make trip page builds the page for the route's trip`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let convertible = try Fixtures.tripConvertible(tripID: "trip_42")

        let page = TripPageSheetHost.makeTripPage(
            application: application,
            tripConvertible: convertible,
            onMapFocusChanged: { _ in },
            onSelectStop: { _ in },
            onClose: {}
        )

        #expect(page.viewModel.tripConvertible === convertible)
        #expect(page.application === application)
    }

    @Test @MainActor
    func `Make trip page hands the page the host's map focus handler`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        var reported: [TripMapFocus?] = []

        let page = TripPageSheetHost.makeTripPage(
            application: application,
            tripConvertible: try Fixtures.tripConvertible(),
            onMapFocusChanged: { reported.append($0) },
            onSelectStop: { _ in },
            onClose: {}
        )
        page.onMapFocusChanged?(page.mapFocus)

        #expect(reported.count == 1)
        #expect(reported.first.flatMap { $0 } === page.mapFocus)
    }

    @Test @MainActor
    func `Make trip page hands the page the host's close`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        var closeCount = 0

        let page = TripPageSheetHost.makeTripPage(
            application: application,
            tripConvertible: try Fixtures.tripConvertible(),
            onMapFocusChanged: { _ in },
            onSelectStop: { _ in },
            onClose: { closeCount += 1 }
        )
        page.onClose?()

        #expect(closeCount == 1)
    }

    /// Driven through the page's own stop action, so it also covers the page
    /// consulting the hook. If the page stopped, the tap would reach
    /// `ViewRouter.navigate(to:from:)`, which asserts a navigation stack this sheet
    /// doesn't have: that regression crashes the run rather than failing a test,
    /// which is why this is kept apart from the others.
    @Test @MainActor
    func `A tapped stop goes to the host`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        var selectedStopIDs: [StopID] = []

        let page = TripPageSheetHost.makeTripPage(
            application: application,
            tripConvertible: try Fixtures.tripConvertible(),
            onMapFocusChanged: { _ in },
            onSelectStop: { selectedStopIDs.append($0) },
            onClose: {}
        )
        page.rootView.actions.onSelectStop("1_75403")

        #expect(selectedStopIDs == ["1_75403"])
    }
}
