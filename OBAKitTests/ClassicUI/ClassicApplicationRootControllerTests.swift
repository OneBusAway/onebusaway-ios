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
        
        // Assert that view controllers are correctly created
        #expect(rootController.mapController != nil)
        #expect(rootController.recentStopsController != nil)
        #expect(rootController.bookmarksController != nil)
        #expect(rootController.moreController != nil)
        
        // Assert that view controllers are wrapped in UINavigationController
        let navControllers = rootController.viewControllers as? [UINavigationController]
        #expect(navControllers?.count == 4)
        
        if let navControllers, navControllers.count == 4 {
            #expect(navControllers[0].viewControllers.first === rootController.mapController)
            #expect(navControllers[1].viewControllers.first === rootController.recentStopsController)
            #expect(navControllers[2].viewControllers.first === rootController.bookmarksController)
            #expect(navControllers[3].viewControllers.first === rootController.moreController)
        }
        
        // The root controller should be registered in the ViewRouter
        #expect(application.viewRouter.rootController === rootController)
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
}
