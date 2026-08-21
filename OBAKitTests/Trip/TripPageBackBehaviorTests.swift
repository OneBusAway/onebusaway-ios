//
//  TripPageBackBehaviorTests.swift
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

/// Which way out the trip page's Back row takes.
///
/// The regression: tapping a departure on the stop *sheet* presents the trip
/// page as the root of a fresh `UINavigationController`, where the unconditional
/// `popViewController` it shipped with returns nil and does nothing. The rider
/// got a Back button that visibly did nothing, on a modal with swipe-to-dismiss
/// disabled and its navigation bar hidden — no way out at all.
@Suite(.serialized)
struct TripPageBackBehaviorTests {

    @Test func `A page pushed onto an existing stack pops`() {
        #expect(TripPageBackBehavior.forStackDepth(2) == .pop)
        #expect(TripPageBackBehavior.forStackDepth(5) == .pop)
    }

    /// The sheet path: wrapped in its own navigation controller, so it is the
    /// only thing on the stack and there is nothing to pop back to.
    @Test func `A page that is the root of its own stack dismisses`() {
        #expect(TripPageBackBehavior.forStackDepth(1) == .dismiss)
    }

    /// Presented bare, with no navigation controller at all.
    @Test func `A page with no navigation stack dismisses`() {
        #expect(TripPageBackBehavior.forStackDepth(0) == .dismiss)
    }

    /// The glyph has to promise what the button does. A chevron on the modal
    /// presentation offered to go "back" to a screen that was never there.
    @Test func `Popping wears a chevron and dismissing wears a close`() {
        #expect(TripPageBackBehavior.pop.systemImage == "chevron.backward")
        #expect(TripPageBackBehavior.dismiss.systemImage == "xmark")
    }
}

/// The wiring: that `TripPageViewController` actually resolves its Back row
/// against the stack it is in, rather than always popping.
@MainActor
@Suite(.serialized)
final class TripPageBackWiringTests: OBATestCase {

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

    /// The sheet path.
    @Test func `Wrapped in its own navigation controller the page dismisses`() throws {
        let page = try makeTripPage()
        let navigation = UINavigationController(rootViewController: page)

        #expect(navigation.viewControllers.count == 1)
        #expect(page.backBehavior == .dismiss)
    }

    /// The pushed path, from the Stop page.
    @Test func `Pushed onto an existing stack the page pops`() throws {
        let page = try makeTripPage()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(page, animated: false)

        #expect(navigation.viewControllers.count == 2)
        #expect(page.backBehavior == .pop)
    }
}
