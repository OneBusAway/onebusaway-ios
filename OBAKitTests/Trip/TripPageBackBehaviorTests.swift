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
        try TripPageFixture.makePage(
            application: buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
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

    /// The map panel's sheet, which hosts the page with no stack at all. SwiftUI
    /// presented it and the sheet coordinator holds its route, so Back asks the
    /// host rather than dismissing from UIKit.
    @Test func `With no stack, Back asks a host that owns the presentation to close`() throws {
        let page = try makeTripPage()
        var closeCount = 0
        page.onClose = { closeCount += 1 }

        page.rootView.actions.onBack()

        #expect(closeCount == 1)
    }

    // MARK: - Entry Routes

    /// The stop entry route: pushed from a stop page onto an existing navigation
    /// stack, Back pops the page and returns to the stop.
    @Test func `Stop entry route pops navigation controller back to stop page`() throws {
        let page = try makeTripPage()
        let stopPage = UIViewController()
        let navigation = UINavigationController(rootViewController: stopPage)
        navigation.pushViewController(page, animated: false)

        #expect(navigation.viewControllers.count == 2)
        #expect(page.backBehavior == .pop)

        page.rootView.actions.onBack()

        #expect(navigation.viewControllers == [stopPage])
        #expect(navigation.topViewController === stopPage)
    }

    /// The trip entry route: when an adjacent or continuation trip is opened from
    /// a trip page on a navigation stack, it is pushed onto the same stack, and Back
    /// pops back to the prior trip while preserving stack depth.
    @Test func `Trip entry route from adjacent trip navigation pops back to prior trip`() throws {
        let page1 = try makeTripPage()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(page1, animated: false)

        let convertible2 = try Fixtures.tripConvertible(tripID: "trip_2")
        page1.openTrip(convertible2)

        #expect(navigation.viewControllers.count == 3)
        let page2 = try #require(navigation.viewControllers.last as? TripPageViewController)
        #expect(page2.viewModel.tripConvertible.tripID == "trip_2")
        #expect(page2.backBehavior == .pop)

        page2.rootView.actions.onBack()

        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController === page1)
        #expect(page1.backBehavior == .pop)

        page1.rootView.actions.onBack()

        #expect(navigation.viewControllers == [root])
    }

    /// The map-focus entry route: `TripMapHostViewController` embeds the page with
    /// a map of its own. When pushed, Back pops the host; when root or bare, Back dismisses.
    @Test func `Map focus entry path in TripMapHostViewController resolves back behavior across stack modes`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let departure = try #require(stopArrivals.arrivalsAndDepartures.first)
        let host = TripMapHostViewController(application: application, arrivalDeparture: departure)
        host.loadViewIfNeeded()

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(host, animated: false)

        #expect(host.tripPage.backBehavior == .pop)
        host.tripPage.rootView.actions.onBack()
        #expect(navigation.viewControllers == [root])

        let modalHost = TripMapHostViewController(application: application, arrivalDeparture: departure)
        modalHost.loadViewIfNeeded()
        let modalNavigation = UINavigationController(rootViewController: modalHost)
        #expect(modalHost.tripPage.navigationController === modalNavigation)
        #expect(modalHost.tripPage.backBehavior == .dismiss)

        let bareHost = TripMapHostViewController(application: application, arrivalDeparture: departure)
        bareHost.loadViewIfNeeded()
        #expect(bareHost.tripPage.backBehavior == .dismiss)
    }

    // MARK: - Nested Stop Selection

    /// Nested stop selection from the trip page pushes the stop controller onto
    /// the navigation stack, and Back from the nested stop returns cleanly to the trip page.
    @Test func `Nested stop selection from trip page preserves navigation hierarchy and unwinds back deterministically`() throws {
        let page = try makeTripPage()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(page, animated: false)

        let stopRow = TripPageFixture.makeStopRow(stopID: "1_75403", name: "Pine St & 5th Ave", sequence: 4)
        page.rootView.actions.onSelectStop(stopRow)

        #expect(navigation.viewControllers.count == 3)
        let stopVC = try #require(navigation.viewControllers.last as? StopPageViewController)
        #expect(stopVC.viewModel.stopID == "1_75403")

        navigation.popViewController(animated: false)

        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController === page)
        #expect(page.backBehavior == .pop)

        page.rootView.actions.onBack()

        #expect(navigation.viewControllers == [root])
    }

    // MARK: - Repeated Back Action

    /// Repeated Back action on a navigation stack: the first call pops the page,
    /// and subsequent calls evaluate safely against the updated stack without crashing.
    @Test func `Repeated back action on navigation stack safely pops without crashing`() throws {
        let page = try makeTripPage()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(page, animated: false)

        #expect(navigation.viewControllers.count == 2)
        #expect(page.backBehavior == .pop)

        page.rootView.actions.onBack()

        #expect(navigation.viewControllers.count == 1)
        #expect(navigation.topViewController === root)

        // Rapid second tap after pop completed: should evaluate safely as dismiss
        page.rootView.actions.onBack()

        #expect(navigation.viewControllers == [root])
    }

    // MARK: - VoiceOver

    /// The control said only "Back", with the origin as separate text after it, so
    /// it sounded like the rider was still on the stop page.
    @Test func `Back names where it goes`() {
        #expect(TripPageBackBehavior.pop.accessibilityLabel(originTitle: "3rd Ave & Pike St") == "Back to 3rd Ave & Pike St")
        #expect(TripPageBackBehavior.pop.accessibilityLabel(originTitle: nil) == Strings.back)
        #expect(TripPageBackBehavior.dismiss.accessibilityLabel(originTitle: "3rd Ave & Pike St") == Strings.close)
    }
}
