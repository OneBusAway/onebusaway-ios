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

    /// A spy recording reloaded widget kinds standing in for `WidgetCenter`,
    /// which can't be observed from a test.
    @MainActor
    private final class ReloadRecorder {
        private(set) var reloadedKinds: [String] = []
        func record(kind: String) { reloadedKinds.append(kind) }
        func reset() { reloadedKinds.removeAll() }
    }

    /// Deleting from anywhere — the tab, the index sheet, Manage Bookmarks —
    /// posts `.bookmarksDidChange`, so one observer covers all of them.
    @Test @MainActor func `Deleting a bookmark reloads widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()
        recorder.reset()

        application.userDataStore.delete(bookmark: bookmark)
        await drainMainActor()

        #expect(recorder.reloadedKinds == BookmarkWidgetRefresher.widgetKinds)
        withExtendedLifetime(refresher) {}
    }

    /// Pinning is the mutation the home sheet's bookmarks section performs, and
    /// it changes what the widget shows, so it must reload too.
    @Test @MainActor func `Pinning a bookmark reloads widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()
        recorder.reset()

        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()

        #expect(recorder.reloadedKinds == BookmarkWidgetRefresher.widgetKinds)
        withExtendedLifetime(refresher) {}
    }

    /// Adding is what the stop page's bookmark flow does. Same store, same
    /// notification, same reload.
    @Test @MainActor func `Adding a bookmark reloads widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()

        #expect(recorder.reloadedKinds == BookmarkWidgetRefresher.widgetKinds)
        withExtendedLifetime(refresher) {}
    }

    /// A no-op write doesn't post, so the widget isn't reloaded for nothing.
    /// `setPinned` guards on the value actually changing.
    @Test @MainActor func `Re-pinning an already-pinned bookmark does not reload`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()
        recorder.reset()

        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()

        #expect(recorder.reloadedKinds.isEmpty)
        withExtendedLifetime(refresher) {}
    }

    /// Deleting a group with multiple bookmarks migrates all of them atomically
    /// and triggers exactly ONE widget reload.
    @Test @MainActor func `Deleting a populated group reloads the widget exactly once`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let group = BookmarkGroup(name: "Test Group", sortOrder: 0)
        application.userDataStore.upsert(bookmarkGroup: group)

        let bm1 = try makeBookmark(application: application)
        let bm2 = try makeBookmark(application: application)
        application.userDataStore.add(bm1, to: group)
        application.userDataStore.add(bm2, to: group)
        await drainMainActor()

        recorder.reset()
        application.userDataStore.deleteGroup(group)
        await drainMainActor()

        #expect(recorder.reloadedKinds == BookmarkWidgetRefresher.widgetKinds, "Must reload widget exactly once for the group deletion")
        withExtendedLifetime(refresher) {}
    }

    /// Failed persistence does not reload the widget.
    @Test @MainActor func `Failed persistence does not reload the widget`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let store = try #require(application.userDataStore as? UserDefaultsStore)
        let recorder = ReloadRecorder()
        let refresher = BookmarkWidgetRefresher(reloadKind: { recorder.record(kind: $0) })

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()
        recorder.reset()

        store.simulatedPersistenceError = NSError(domain: "test.persistence", code: 500, userInfo: nil)
        application.userDataStore.setPinned(true, for: bookmark)
        await drainMainActor()

        #expect(recorder.reloadedKinds.isEmpty)
        withExtendedLifetime(refresher) {}
    }

    /// A single aggregate reload callback is invoked once per timeline refresh event,
    /// even when multiple widget kinds are registered.
    @Test @MainActor func `Aggregate reload callback is invoked once per refresh event`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        var reloadCount = 0
        let refresher = BookmarkWidgetRefresher { reloadCount += 1 }

        let bookmark = try makeBookmark(application: application)
        application.userDataStore.add(bookmark, to: nil)
        await drainMainActor()

        #expect(reloadCount == 1)
        withExtendedLifetime(refresher) {}
    }

    /// The tab's own arrival-batch reload targets the same widget kinds, so the
    /// two paths can't drift apart on the identifiers.
    @Test @MainActor func `Widget kind matches the registered extension kind`() {
        #expect(BookmarkWidgetRefresher.widgetKind == "OBAWidget")
        #expect(BookmarkWidgetRefresher.complicationWidgetKind == "NextDepartureWidget")
        #expect(BookmarkWidgetRefresher.widgetKinds == ["OBAWidget", "NextDepartureWidget"])
    }

    @Test @MainActor func `ReloadAllTimelines reloads every registered widget kind`() {
        var reloadedKinds: [String] = []
        BookmarkWidgetRefresher.reloadAllTimelines(using: { reloadedKinds.append($0) })

        #expect(reloadedKinds == BookmarkWidgetRefresher.widgetKinds)
        #expect(reloadedKinds == ["OBAWidget", "NextDepartureWidget"])
    }
}
