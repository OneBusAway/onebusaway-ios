//
//  TripPageCollapseTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
import OBAKitCore
@testable import OBAKit

/// What the trip page shows at the sheet's `.tip` detent.
///
/// The regression: the page's action bar is pinned as a bottom `safeAreaInset` and is taller than
/// the whole `.tip` detent, so at that detent SwiftUI squeezed out the back row and the stop list
/// and the peek was a Live Activity button floating over the map, naming no trip at all. The page
/// has to be told which detent it is at — `StopSheetPresenter` only tells content that conforms to
/// `StopSheetCollapsibleContent` — and drop the bar there.
@MainActor
@Suite(.serialized)
final class TripPageCollapseTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeTripPage() throws -> TripPageViewController {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        return TripPageViewController(
            application: application,
            tripConvertible: TripConvertible(arrivalDeparture: try Fixtures.arrivalDeparture()),
            originTitle: "3rd Ave & Pike St"
        )
    }

    /// Without this conformance the presenter's detent changes never reach the page, which is
    /// exactly how it ended up rendering its full chrome inside a sliver.
    @Test func `The page is collapsible sheet content`() throws {
        let page = try makeTripPage()
        #expect(page as? StopSheetCollapsibleContent != nil)
    }

    /// Expanded is the state the page is built in: every other detent has room for the bar.
    @Test func `The page starts expanded`() throws {
        let page = try makeTripPage()
        #expect(page.rootView.isCollapsed == false)
    }

    @Test func `Moving to the tip detent collapses the page`() throws {
        let page = try makeTripPage()

        page.setAtTip(true)
        #expect(page.rootView.isCollapsed)

        page.setAtTip(false)
        #expect(page.rootView.isCollapsed == false)
    }
}
