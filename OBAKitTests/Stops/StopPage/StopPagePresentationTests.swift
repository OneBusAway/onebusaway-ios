//
//  StopPagePresentationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing

/// The Stop page has two presentations: pushed onto a navigation stack (dark map header, chrome in
/// the navigation bar) and presented as a sheet over the map (light header, chrome in a bottom
/// toolbar). `showToolbarOnBottom` is the only thing that selects between them.
///
/// The load-bearing requirement is the *pushed* side: it must be untouched by this work. These
/// tests pin that down at the two seams where it could silently change — the router's default and
/// the navigation-bar items.
@MainActor
@Suite(.serialized)
final class StopPagePresentationTests: OBATestCase {

    private var queue: OperationQueue!
    private var application: Application!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        userDefaults.set(true, forKey: FeatureFlags.useNewStopPageKey)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func makeStop() throws -> Stop {
        try #require(Fixtures.loadSomeStops().first)
    }

    // MARK: - Router defaults

    /// Everything that pushes — Recents, Bookmarks, the map drawer's list, transfers — calls
    /// `makeStopController` without the new argument. If the default ever flips, all of them
    /// silently acquire a bottom toolbar.
    @Test func `Make stop controller defaults to the pushed presentation`() throws {
        let stop = try makeStop()

        let byStop = application.viewRouter.makeStopController(stop: stop) as? StopPageViewController
        let byID = application.viewRouter.makeStopController(stopID: stop.id) as? StopPageViewController

        #expect(byStop?.showsBottomToolbar == false)
        #expect(byID?.showsBottomToolbar == false)
    }

    @Test func `Make stop controller opts into the sheet presentation`() throws {
        let stop = try makeStop()

        let byStop = application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true) as? StopPageViewController
        let byID = application.viewRouter.makeStopController(stopID: stop.id, showToolbarOnBottom: true) as? StopPageViewController

        #expect(byStop?.showsBottomToolbar == true)
        #expect(byID?.showsBottomToolbar == true)
    }

    /// The legacy screen has only the pushed layout, so the flag must be inert there rather than
    /// producing a `StopViewController` that someone later assumes has a toolbar.
    @Test func `Legacy screen ignores the sheet flag`() throws {
        userDefaults.set(false, forKey: FeatureFlags.useNewStopPageKey)
        let stop = try makeStop()

        let controller = application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true)

        #expect(controller is StopViewController)
    }

    // MARK: - Navigation bar chrome

    /// The pushed page keeps its three right-hand bar items. This is the assertion that fails if
    /// the sheet's chrome suppression ever leaks across.
    @Test func `Pushed presentation keeps its navigation bar items`() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop())
        controller.loadViewIfNeeded()

        #expect(controller.navigationItem.rightBarButtonItems?.count == 3)
    }

    /// The sheet installs no bar items — they would duplicate the toolbar's controls inside a
    /// navigation bar that renders as a bare grabber.
    @Test func `Sheet presentation installs no navigation bar items`() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop(), showToolbarOnBottom: true)
        controller.loadViewIfNeeded()

        #expect(controller.navigationItem.rightBarButtonItems == nil)
    }

    // MARK: - Preview mode

    /// A peek is a bare glance in both presentations.
    @Test func `Preview mode suppresses chrome in both presentations`() throws {
        let stop = try makeStop()

        let pushed = StopPageViewController(application: application, stop: stop)
        pushed.loadViewIfNeeded()
        pushed.enterPreviewMode()
        #expect(pushed.navigationItem.rightBarButtonItems == nil)

        let sheet = StopPageViewController(application: application, stop: stop, showToolbarOnBottom: true)
        sheet.loadViewIfNeeded()
        sheet.enterPreviewMode()
        #expect(!sheet.showsBottomToolbar)

        // Committing the peek restores the toolbar, since the same instance is what gets
        // presented in the sheet.
        sheet.exitPreviewMode()
        #expect(sheet.showsBottomToolbar)
    }

    /// Leaving a preview must put the pushed page's bar items back, not leave it bare.
    @Test func `Exiting preview mode restores pushed navigation bar items`() throws {
        let controller = StopPageViewController(application: application, stop: try makeStop())
        controller.loadViewIfNeeded()

        controller.enterPreviewMode()
        controller.exitPreviewMode()

        #expect(controller.navigationItem.rightBarButtonItems?.count == 3)
    }
}
