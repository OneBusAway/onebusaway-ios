//
//  SceneRestorationActivityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import App
@testable import OBAKit

/// A scene saves the activity its walk of the view controller tree finds. A
/// stop page in the map sheet is FloatingPanel content: a child view controller,
/// neither presented nor pushed. Plain view controllers added with `addChild`
/// stand in for the panel here.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1556
@MainActor
@Suite(.serialized)
final class SceneRestorationActivityTests: OBATestCase {

    private var queue: OperationQueue!
    private var stopActivityType: String!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        stopActivityType = try #require(application.userActivityBuilder).stopActivityType
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// A view controller publishing its own stop activity, as a stop page does.
    private func makePage() -> (UIViewController, NSUserActivity) {
        let page = UIViewController()
        let activity = NSUserActivity(activityType: stopActivityType)
        page.userActivity = activity
        return (page, activity)
    }

    /// The map sheet's shape: map, then panel, then the panel's navigation stack.
    @Test func `Restoration finds a stop page inside a child container`() {
        let (page, activity) = makePage()
        let root = UIViewController()
        let container = UIViewController()
        root.addChild(container)
        container.addChild(UINavigationController(rootViewController: page))

        #expect(SceneDelegate.userActivity(for: root) === activity)
    }

    /// A tab bar's `children` is every tab, so descending into them would
    /// restore a tab the rider isn't on. The first expectation fails without the
    /// descent into children; the second fails if the descent includes tab bars.
    @Test func `Restoration follows the selected tab, not every tab`() {
        let (selectedPage, selectedActivity) = makePage()
        let selectedTab = UIViewController()
        selectedTab.addChild(selectedPage)

        let (otherPage, _) = makePage()
        let otherTab = UIViewController()
        otherTab.addChild(otherPage)

        let emptyTab = UIViewController()

        let tabBar = UITabBarController()
        tabBar.viewControllers = [selectedTab, otherTab, emptyTab]

        tabBar.selectedViewController = selectedTab
        #expect(SceneDelegate.userActivity(for: tabBar) === selectedActivity)

        // Nothing to restore on the selected tab, and the other tab's activity
        // must not stand in for it.
        tabBar.selectedViewController = emptyTab
        #expect(SceneDelegate.userActivity(for: tabBar) == nil)
    }

    /// `MapViewController` adds the stop sheet's panel after its own children,
    /// and the sheet is the one on top.
    @Test func `Restoration prefers the most recently added child`() {
        let (first, _) = makePage()
        let (last, lastActivity) = makePage()
        let root = UIViewController()
        root.addChild(first)
        root.addChild(last)

        #expect(SceneDelegate.userActivity(for: root) === lastActivity)
    }
}
