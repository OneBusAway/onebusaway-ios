//
//  ClassicApplicationRootControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
@MainActor
final class ClassicApplicationRootControllerTests: OBATestCase {

    @Test func testInitializationAndViewControllers() {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        
        let rootController = ClassicApplicationRootController(application: application)
        
        // Assert that view controllers are wrapped in UINavigationController
        let navControllers = rootController.viewControllers as? [UINavigationController]
        #expect(navControllers?.count == 4)
        
        if let navControllers, navControllers.count == 4 {
            #expect(navControllers[0].viewControllers.first === rootController.mapController)
            #expect(navControllers[1].viewControllers.first === rootController.recentStopsController)
            #expect(navControllers[2].viewControllers.first === rootController.bookmarksController)
            #expect(navControllers[3].viewControllers.first === rootController.moreController)
        }
        
        // The root controller should be resolved by the ViewRouter
        #expect(application.viewRouter.rootController(from: rootController) === rootController)
        #expect(application.viewRouter.rootController(from: rootController.mapController) === rootController)
        #expect(application.viewRouter.rootController === rootController)
        
        // Assert initial selected tab from persisted store (defaults to map)
        #expect(rootController.selectedIndex == ClassicApplicationRootController.Page.map.rawValue)
    }

    @Test func testNavigation() {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        
        let rootController = ClassicApplicationRootController(application: application)
        
        rootController.navigate(to: .bookmarks)
        #expect(rootController.selectedIndex == ClassicApplicationRootController.Page.bookmarks.rawValue)
        
        rootController.navigate(to: .recentStops)
        #expect(rootController.selectedIndex == ClassicApplicationRootController.Page.recentStops.rawValue)
    }

    @Test func testMultiWindowRootControllerResolution() {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root1 = ClassicApplicationRootController(application: application)
        let window1 = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window1.rootViewController = root1

        let root2 = ClassicApplicationRootController(application: application)
        let window2 = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window2.rootViewController = root2

        // Resolving from child controllers in window 1 returns root1
        #expect(application.viewRouter.rootController(from: root1.recentStopsController) === root1)
        #expect(application.viewRouter.rootController(from: root1) === root1)

        // Resolving from child controllers in window 2 returns root2
        #expect(application.viewRouter.rootController(from: root2.recentStopsController) === root2)
        #expect(application.viewRouter.rootController(from: root2) === root2)

        // Calling rootNavigateTo from root1 only navigates root1
        application.viewRouter.rootNavigateTo(page: .bookmarks, from: root1.recentStopsController)
        #expect(root1.selectedIndex == ClassicApplicationRootController.Page.bookmarks.rawValue)
        #expect(root2.selectedIndex == ClassicApplicationRootController.Page.map.rawValue)
    }

    @Test func testRootControllerNotStronglyRetainedByRouter() {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        weak var weakRoot: ClassicApplicationRootController?
        autoreleasepool {
            let root = ClassicApplicationRootController(application: application)
            weakRoot = root
            #expect(application.viewRouter.rootController(from: root) === root)
        }

        #expect(weakRoot == nil)
    }
}
