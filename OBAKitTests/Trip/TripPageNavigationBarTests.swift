//
//  TripPageNavigationBarTests.swift
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

/// The trip page hides its navigation controller's bar, because it draws its own
/// back row. It has to hand the bar back when it leaves the screen.
///
/// The regression (#1570): it hid the bar and never restored it. The map's stop sheet
/// re-decides the bar on every push and pop, so it coped, but a stack with no such
/// handler, such as the Recent tab's, brought the stop page back with no bar: no back
/// button, no Schedules, Filter or More.
@MainActor
@Suite(.serialized)
final class TripPageNavigationBarTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow?

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
        window?.rootViewController = nil
        window?.isHidden = true
    }

    /// - Parameter barsVertical: Whether the system presents bars vertically, as on
    ///   iPhone Duo. Pinned either way so the suite means the same on every simulator.
    private func makeTripPage(barsVertical: Bool = false) throws -> TripPageViewController {
        let page = try TripPageFixture.makeOnScreenPage(
            application: buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        )
        page.presentsBarsVerticallyOverride = barsVertical
        return page
    }

    /// A stack on screen, so pushes and pops run the appearance callbacks.
    private func show(_ navigation: UINavigationController) throws -> UIWindow {
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        self.window = window
        return window
    }

    private func push(_ viewController: UIViewController, onto navigation: UINavigationController, in window: UIWindow) {
        navigation.pushViewController(viewController, animated: false)
        window.layoutIfNeeded()
    }

    private func pop(_ navigation: UINavigationController, in window: UIWindow) {
        navigation.popViewController(animated: false)
        window.layoutIfNeeded()
    }

    @Test func `The page hides the bar while it is on screen`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)

        #expect(navigation.isNavigationBarHidden)
    }

    /// The Recent and Bookmarks path: the page the rider backs out to had a bar.
    @Test func `Popping the page gives the page underneath its bar back`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)
        #expect(!navigation.isNavigationBarHidden)

        push(try makeTripPage(), onto: navigation, in: window)
        pop(navigation, in: window)

        #expect(!navigation.isNavigationBarHidden)
    }

    /// A host that had hidden the bar itself gets it back hidden, not shown.
    @Test func `Popping the page leaves a bar the host had hidden still hidden`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        pop(navigation, in: window)

        #expect(navigation.isNavigationBarHidden)
    }

    /// A stop opened from the trip page's stop list is pushed on top of it, and needs
    /// its own bar for its back button and actions.
    @Test func `A page pushed on top of the trip page gets the bar`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        push(UIViewController(), onto: navigation, in: window)

        #expect(!navigation.isNavigationBarHidden)
    }

    /// The host's "hidden" is for the host, not for a page pushed over the trip page,
    /// which still needs its bar; it's handed back only when the trip page goes.
    @Test func `Over a host that had hidden the bar, a page pushed on top still gets it`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        push(UIViewController(), onto: navigation, in: window)
        #expect(!navigation.isNavigationBarHidden)

        pop(navigation, in: window)
        #expect(navigation.isNavigationBarHidden)
        pop(navigation, in: window)
        #expect(navigation.isNavigationBarHidden)
    }

    @Test func `Coming back to the trip page hides the bar again`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        push(UIViewController(), onto: navigation, in: window)
        pop(navigation, in: window)

        #expect(navigation.isNavigationBarHidden)
    }

    /// The full round trip from the issue: back out of the stop pushed over the trip
    /// page, then out of the trip page.
    @Test func `Backing all the way out restores the original bar`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        push(UIViewController(), onto: navigation, in: window)
        pop(navigation, in: window)
        pop(navigation, in: window)

        #expect(!navigation.isNavigationBarHidden)
    }

    // MARK: - Vertical bars (iPhone Duo)

    /// The bar costs no height in a vertical column, and its back button belongs
    /// there with the tabs, so the page shows it and drops its own back row.
    @Test func `With vertical bars the page shows the system bar instead of its back row`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        let page = try makeTripPage(barsVertical: true)
        push(page, onto: navigation, in: window)

        #expect(!navigation.isNavigationBarHidden)
        #expect(!page.rootView.showsBackRow)
    }

    @Test func `With vertical bars, popping the page still restores the host's bar`() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        push(try makeTripPage(barsVertical: true), onto: navigation, in: window)
        pop(navigation, in: window)

        #expect(navigation.isNavigationBarHidden)
    }

    // MARK: - A stack whose delegate decides the bar

    /// What `StopSheetPresenter` does: decides the bar on every push and pop.
    private final class BarDecidingDelegate: NSObject, UINavigationControllerDelegate {
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            navigationController.setNavigationBarHidden(viewController is SelfChromedRoot || viewController is TripPageViewController, animated: animated)
        }
    }

    /// Like the stop sheet's own root, which draws its own header.
    private final class SelfChromedRoot: UIViewController {}

    /// The stop sheet: its root hides the bar, so the trip page would have saved
    /// "hidden" and put it back over a page that wants it.
    @Test func `In a stack whose delegate decides the bar, a page pushed on top gets it`() throws {
        let delegate = BarDecidingDelegate()
        let navigation = UINavigationController(rootViewController: SelfChromedRoot())
        navigation.delegate = delegate
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        push(try makeTripPage(), onto: navigation, in: window)
        #expect(navigation.isNavigationBarHidden)
        push(UIViewController(), onto: navigation, in: window)
        #expect(!navigation.isNavigationBarHidden)
        pop(navigation, in: window)
        #expect(navigation.isNavigationBarHidden)
        withExtendedLifetime(delegate) {}
    }
}
