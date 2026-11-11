//
//  BookmarkActionsExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `BookmarkActions` deletion analytics, activity key formatting,
/// and edge cases around nameless or route-less bookmarks.
@Suite(.serialized)
final class BookmarkActionsExtendedTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private static let seedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func makeStop(id: String = "1_100", name: String = "4th & Pike") -> Stop {
        Stop(
            id: id,
            name: name,
            coordinate: TestData.mockSeattleCoordinate,
            direction: "NB",
            routeIDs: ["1_10", "1_44"],
            routes: []
        )
    }

    @MainActor
    private func makeStopBookmark(application: Application, name: String = "My Stop") -> Bookmark {
        let bookmark = Bookmark(
            name: name,
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: makeStop(),
            dateCreated: Self.seedDate
        )
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    @Test @MainActor
    func `Deleting a bookmark without route or headsign does not emit unstar event`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let analytics = app.analytics as? AnalyticsMock
        let bookmark = makeStopBookmark(application: app, name: "Downtown Stop")

        let actions = BookmarkActions(application: app)
        let countBefore = analytics?.reportedEvents.count ?? 0

        actions.reportDeletion(of: bookmark)

        #expect((analytics?.reportedEvents.count ?? 0) == countBefore)
    }

    @Test @MainActor
    func `Multiple bookmark deletions of stop bookmarks emit no analytics`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let analytics = app.analytics as? AnalyticsMock
        let b1 = makeStopBookmark(application: app, name: "Stop 1")
        let b2 = makeStopBookmark(application: app, name: "Stop 2")

        let actions = BookmarkActions(application: app)
        actions.reportDeletion(of: b1)
        actions.reportDeletion(of: b2)

        #expect((analytics?.reportedEvents.count ?? 0) == 0)
    }

    @Test @MainActor
    func `BookmarkActions initializes cleanly with Application`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let actions = BookmarkActions(application: app)
        #expect(actions.application === app)
    }
}
