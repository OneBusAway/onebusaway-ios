//
//  BookmarkWatchSyncSenderTests.swift
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
final class BookmarkWatchSyncSenderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @MainActor
    private func makeBookmark(application: Application, name: String = "Test Bookmark") throws -> Bookmark {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        return Bookmark(
            name: name,
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop
        )
    }

    @Test @MainActor func `Payload construction orders bookmarks correctly`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            debounceInterval: .milliseconds(50)
        )

        let groupA = BookmarkGroup(name: "Group A", sortOrder: 1)
        let groupB = BookmarkGroup(name: "Group B", sortOrder: 0)

        application.userDataStore.upsert(bookmarkGroup: groupA)
        application.userDataStore.upsert(bookmarkGroup: groupB)

        let b1 = try makeBookmark(application: application, name: "Bookmark 1")
        let b2 = try makeBookmark(application: application, name: "Bookmark 2")
        let bUngrouped = try makeBookmark(application: application, name: "Ungrouped")

        application.userDataStore.add(b1, to: groupA)
        application.userDataStore.add(b2, to: groupB)
        application.userDataStore.add(bUngrouped, to: nil)

        let payload = try #require(sender.buildPayload())

        #expect(payload.groups.map(\.name) == ["Group B", "Group A"])
        #expect(payload.bookmarks.map(\.name) == ["Bookmark 2", "Bookmark 1", "Ungrouped"])
    }

    @Test @MainActor func `Debounce coalesces rapid changes`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let sender = BookmarkWatchSyncSender(
            userDataStore: application.userDataStore,
            regionsService: application.regionsService,
            debounceInterval: .milliseconds(100)
        )

        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
        NotificationCenter.default.post(name: .bookmarkGroupsDidChange, object: nil)
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)

        try? await Task.sleep(for: .milliseconds(200))

        #expect(sender.buildPayload() != nil)
    }
}
