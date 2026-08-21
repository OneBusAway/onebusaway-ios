//
//  BookmarkWidgetRefresherTests.swift
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

/// The widget renders bookmarks, so it must be reloaded whenever the bookmark
/// set changes — from *any* surface, not just the Bookmarks tab. These assert
/// the store-level trigger rather than any one screen's call site, which is the
/// whole point of observing the notification.
@Suite(.serialized)
final class BookmarkWidgetRefresherTests: OBATestCase {

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
    private func makeBookmark(application: Application, name: String = "Bookmark") throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        return Bookmark(
            name: name,
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop,
            dateCreated: Self.seedEpoch
        )
    }

    /// A counting spy standing in for `WidgetCenter`, which can't be observed
    /// from a test.
    @MainActor
    private final class ReloadCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    /// Waits for the refresher's `Task { @MainActor in … }` hop to land. The
    /// notification may be posted off the main actor, so the reload is
    /// deliberately asynchronous.
    @MainActor
    private func drainMainActor() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
    }

    /// Deleting from anywhere — the tab, the index sheet, Manage Bookmarks —
    /// posts `.bookmarksDidChange`, so one observer covers all of them.
    @Test @MainActor func `Deleting a bookmark reloads the widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let counter = ReloadCounter()
        let refresher = BookmarkWidgetRefresher { counter.increment() }

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()
        let afterAdd = counter.count

        application.userDataStore.delete(bookmark: bookmark)
        await drainMainActor()

        #expect(counter.count > afterAdd)
        withExtendedLifetime(refresher) {}
    }

    /// Pinning is the mutation the home sheet's bookmarks section performs, and
    /// it changes what the widget shows, so it must reload too.
    @Test @MainActor func `Pinning a bookmark reloads the widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let counter = ReloadCounter()
        let refresher = BookmarkWidgetRefresher { counter.increment() }

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()
        let afterAdd = counter.count

        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()

        #expect(counter.count > afterAdd)
        withExtendedLifetime(refresher) {}
    }

    /// Adding is what the stop page's bookmark flow does. Same store, same
    /// notification, same reload.
    @Test @MainActor func `Adding a bookmark reloads the widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let counter = ReloadCounter()
        let refresher = BookmarkWidgetRefresher { counter.increment() }

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()

        #expect(counter.count > 0)
        withExtendedLifetime(refresher) {}
    }

    /// A no-op write doesn't post, so the widget isn't reloaded for nothing.
    /// `setPinned` guards on the value actually changing.
    @Test @MainActor func `Re-pinning an already-pinned bookmark does not reload`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let counter = ReloadCounter()
        let refresher = BookmarkWidgetRefresher { counter.increment() }

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()
        let settled = counter.count

        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()

        #expect(counter.count == settled)
        withExtendedLifetime(refresher) {}
    }

    /// The tab's own arrival-batch reload targets the same widget kind, so the
    /// two paths can't drift apart on the identifier.
    @Test @MainActor func `Widget kind matches the registered extension kind`() {
        #expect(BookmarkWidgetRefresher.widgetKind == "OBAWidget")
    }
}
