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
        try TripPageFixture.makePage(
            application: buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        )
    }

    /// Expanded is the state the page is built in: every detent but `.tip` has room for the bar.
    @Test func `The page starts expanded`() throws {
        let page = try makeTripPage()
        #expect(page.rootView.isCollapsed == false)
    }

    /// Driven through the protocol deliberately: the presenter reaches the page as a
    /// `StopSheetCollapsibleContent` and nothing else, so this asserts the conformance the
    /// presenter needs as much as the toggle itself.
    @Test func `Moving to the tip detent collapses the page and back again expands it`() throws {
        let page = try makeTripPage()
        let collapsible: StopSheetCollapsibleContent = page

        collapsible.setAtTip(true)
        #expect(page.rootView.isCollapsed)

        collapsible.setAtTip(false)
        #expect(page.rootView.isCollapsed == false)
    }
}
