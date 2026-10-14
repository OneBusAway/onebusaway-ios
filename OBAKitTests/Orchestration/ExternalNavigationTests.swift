//
//  ExternalNavigationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit

/// `Application.basePresenter(of:)` picks the controller that deep links dismiss
/// before pushing a stop or trip page. These pin down who UIKit says presented
/// what, because the tab root does not always own the presentation.
@MainActor
@Suite(.serialized)
final class ExternalNavigationTests {
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    private let tabs = UITabBarController()
    private let tabContent = UIViewController()

    init() async throws {
        tabs.viewControllers = [UINavigationController(rootViewController: tabContent)]
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // `.overCurrentContext` presentation fails until the tab's view is in the window.
        try await Task.sleep(for: .milliseconds(100))
    }

    isolated deinit {
        window.isHidden = true
    }

    private func present(_ controller: UIViewController, from presenter: UIViewController) async throws {
        presenter.present(controller, animated: false)
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func `Not presented has no base presenter`() {
        #expect(Application.basePresenter(of: tabContent) == nil)
    }

    @Test func `A popover from a tab's content is owned by the tab root`() async throws {
        let popover = UIViewController()
        popover.modalPresentationStyle = .popover
        popover.popoverPresentationController?.sourceView = tabContent.view
        try await present(popover, from: tabContent)

        #expect(window.topViewController === popover)
        #expect(Application.basePresenter(of: popover) === tabs)
    }

    @Test func `A stacked modal resolves to the bottom of the stack`() async throws {
        let first = UIViewController()
        try await present(first, from: tabContent)
        let second = UIViewController()
        try await present(second, from: first)

        #expect(window.topViewController === second)
        #expect(Application.basePresenter(of: second) === tabs)
    }

    /// An active `UISearchController` hosted by a `definesPresentationContext`
    /// controller (Nearby Stops, the route picker) presents this way. The tab
    /// root reports nothing presented, so it cannot be the one to dismiss.
    @Test func `A presentation-context child owns its own presentation`() async throws {
        tabContent.definesPresentationContext = true
        let overlay = UIViewController()
        overlay.modalPresentationStyle = .overCurrentContext
        try await present(overlay, from: tabContent)

        #expect(tabs.presentedViewController == nil)
        #expect(window.topViewController === overlay)
        #expect(window.topViewController?.navigationController == nil)
        #expect(Application.basePresenter(of: overlay) === tabContent)

        tabContent.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.topViewController === tabContent)
        #expect(tabContent.navigationController != nil)
    }
}
