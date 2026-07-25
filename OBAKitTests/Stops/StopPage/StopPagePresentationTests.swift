//
//  StopPagePresentationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore
import Nimble

/// The Stop page has two presentations: pushed onto a navigation stack (dark map header, chrome in
/// the navigation bar) and presented as a sheet over the map (light header, chrome in a bottom
/// toolbar). `showToolbarOnBottom` is the only thing that selects between them.
///
/// The load-bearing requirement is the *pushed* side: it must be untouched by this work. These
/// tests pin that down at the two seams where it could silently change — the router's default and
/// the navigation-bar items.
@MainActor
class StopPagePresentationTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
    }

    override func tearDown() async throws {
        queue.cancelAllOperations()
        queue = nil
        application = nil
        try await super.tearDown()
    }

    private func makeStop() throws -> Stop {
        try XCTUnwrap(Fixtures.loadSomeStops().first)
    }

    // MARK: - Router defaults

    /// Everything that pushes — Recents, Bookmarks, the map drawer's list, transfers — calls
    /// `makeStopController` without the new argument. If the default ever flips, all of them
    /// silently acquire a bottom toolbar.
    func test_makeStopController_defaultsToThePushedPresentation() throws {
        let stop = try makeStop()

        let byStop = application.viewRouter.makeStopController(stop: stop) as? StopPageViewController
        let byID = application.viewRouter.makeStopController(stopID: stop.id) as? StopPageViewController

        expect(byStop?.showsBottomToolbar).to(beFalse())
        expect(byID?.showsBottomToolbar).to(beFalse())
    }

    func test_makeStopController_optsIntoTheSheetPresentation() throws {
        let stop = try makeStop()

        let byStop = application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true) as? StopPageViewController
        let byID = application.viewRouter.makeStopController(stopID: stop.id, showToolbarOnBottom: true) as? StopPageViewController

        expect(byStop?.showsBottomToolbar).to(beTrue())
        expect(byID?.showsBottomToolbar).to(beTrue())
    }

    /// The legacy screen has only the pushed layout, so the flag must be inert there rather than
    /// producing a `StopViewController` that someone later assumes has a toolbar.
    func test_legacyScreen_ignoresTheSheetFlag() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let stop = try makeStop()

        let controller = application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true)

        expect(controller).to(beAKindOf(StopViewController.self))
    }

    // MARK: - Navigation bar chrome

    /// The pushed page keeps its three right-hand bar items. This is the assertion that fails if
    /// the sheet's chrome suppression ever leaks across.
    func test_pushedPresentation_keepsItsNavigationBarItems() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop())
        controller.loadViewIfNeeded()

        expect(controller.navigationItem.rightBarButtonItems?.count).to(equal(3))
    }

    /// The sheet installs no bar items — they would duplicate the toolbar's controls inside a
    /// navigation bar that renders as a bare grabber.
    func test_sheetPresentation_installsNoNavigationBarItems() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop(), showToolbarOnBottom: true)
        controller.loadViewIfNeeded()

        expect(controller.navigationItem.rightBarButtonItems).to(beNil())
    }

    // MARK: - Preview mode

    /// A peek is a bare glance in both presentations.
    func test_previewMode_suppressesChromeInBothPresentations() throws {
        let stop = try makeStop()

        let pushed = StopPageViewController(application: application, stop: stop)
        pushed.loadViewIfNeeded()
        pushed.enterPreviewMode()
        expect(pushed.navigationItem.rightBarButtonItems).to(beNil())

        let sheet = StopPageViewController(application: application, stop: stop, showToolbarOnBottom: true)
        sheet.loadViewIfNeeded()
        sheet.enterPreviewMode()
        expect(sheet.showsBottomToolbar).to(beFalse())

        // Committing the peek restores the toolbar, since the same instance is what gets
        // presented in the sheet.
        sheet.exitPreviewMode()
        expect(sheet.showsBottomToolbar).to(beTrue())
    }

    /// Leaving a preview must put the pushed page's bar items back, not leave it bare.
    func test_exitingPreviewMode_restoresPushedNavigationBarItems() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop())
        controller.loadViewIfNeeded()

        controller.enterPreviewMode()
        controller.exitPreviewMode()

        expect(controller.navigationItem.rightBarButtonItems?.count).to(equal(3))
    }
}
