//
//  BookmarksSheetViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BookmarksSheetViewTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private static let seedEpoch = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func seedBookmark(application: Application) throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        let bookmark = Bookmark(
            name: "Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop,
            dateCreated: Self.seedEpoch
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Builds the handler the sheet installs, with inert presentation callbacks.
    @MainActor
    private func makeHandler(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute>
    ) -> BookmarksNavigationHandler {
        BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: coordinator,
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { _ in },
            onTrackFailure: { }
        )
    }

    /// A tapped bookmark stacks the stop details sheet on the coordinator —
    /// not a `viewRouter` push, which would open a UIKit stop page inside the
    /// sheet and diverge from every other row tap in the sheet system.
    @Test @MainActor func `Selecting a bookmark pushes stop details`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        makeHandler(application: application, coordinator: coordinator)
            .selectBookmark(bookmark)

        #expect(coordinator.stackedRoutes == [.stopDetails(stopID: bookmark.stopID)])
    }

    /// Pinning from the sheet writes through to the store, which is what the
    /// home sheet's bookmarks preview reads.
    @Test @MainActor func `Toggling a pin writes through to the store`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        try #require(!bookmark.isPinned)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        let handler = makeHandler(application: application, coordinator: coordinator)
        handler.togglePin(bookmark)

        let stored = try #require(application.userDataStore.bookmarks.first { $0.id == bookmark.id })
        #expect(stored.isPinned)

        handler.togglePin(stored)
        let unpinned = try #require(application.userDataStore.bookmarks.first { $0.id == bookmark.id })
        #expect(!unpinned.isPinned)
    }

    /// Deleting removes the bookmark from the store.
    @Test @MainActor func `Deleting a bookmark removes it from the store`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        makeHandler(application: application, coordinator: coordinator)
            .deleteBookmark(bookmark)

        #expect(!application.userDataStore.bookmarks.contains { $0.id == bookmark.id })
    }

    /// Editing routes to the presentation callback the sheet supplies rather
    /// than presenting anything itself.
    @Test @MainActor func `Editing a bookmark calls the presentation callback`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        var edited: Bookmark?

        let handler = BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: SheetCoordinator<AppSheetRoute>(root: .home),
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { edited = $0 },
            onTrackFailure: { }
        )
        handler.editBookmark(bookmark)

        #expect(edited?.id == bookmark.id)
    }

    /// Tracking a bookmark with no loaded arrivals can't start an activity, so
    /// the failure callback fires and the sheet can raise its alert.
    @Test @MainActor func `Track failure calls the failure callback`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let bookmark = try seedBookmark(application: application)
        var failed = false

        let handler = BookmarksSheetView.makeNavigationHandler(
            application: application,
            viewModel: BookmarksViewModel(application: application),
            actions: BookmarkActions(application: application),
            coordinator: SheetCoordinator<AppSheetRoute>(root: .home),
            feedback: DataLoadFeedbackGenerator(application: application),
            onEdit: { _ in },
            onTrackFailure: { failed = true }
        )
        handler.trackBookmark(bookmark)

        #expect(failed)
    }
}
