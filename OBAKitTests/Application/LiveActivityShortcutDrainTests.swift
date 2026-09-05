//
//  LiveActivityShortcutDrainTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import ActivityKit
@testable import OBAKit
@testable import OBAKitCore

/// The Track Bookmark Shortcut must start from `Application`, not only from
/// `BookmarksViewController`. Switching the tab index does not pop a pushed
/// stop page, so the tab's consume sites are unreachable (#1222).
@MainActor
@Suite(.serialized)
final class LiveActivityShortcutDrainTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// A missing bookmark is dropped without ActivityKit. The store
    /// notification must consume it — `openAppWhenRun` already fired
    /// `applicationDidBecomeActive` against an empty queue.
    @Test func `store notification consumes a pending shortcut without the Bookmarks tab`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = buildApplication(queue: queue, dataLoader: dataLoader)
        #expect(app.viewRouter.rootController == nil)

        LiveActivityShortcutRequest.store(UUID(), userDefaults: app.userDefaults)

        #expect(LiveActivityShortcutRequest.peek(userDefaults: app.userDefaults) == nil)
    }

    /// Cold launch writes the request before `Application` observes. Drain
    /// from `rootUserInterfaceDidLoad` without selecting the Bookmarks tab.
    @Test func `rootUserInterfaceDidLoad consumes a queued shortcut written without a notification`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = buildApplication(queue: queue, dataLoader: dataLoader)
        let missing = UUID()
        app.userDefaults.set(missing.uuidString, forKey: LiveActivityShortcutRequest.userDefaultsKey)
        app.userDefaults.set(Date().timeIntervalSince1970, forKey: LiveActivityShortcutRequest.storedAtKey)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: app.userDefaults) == missing)

        app.rootUserInterfaceDidLoad()

        #expect(LiveActivityShortcutRequest.peek(userDefaults: app.userDefaults) == nil)
    }

    /// A known trip bookmark whose arrivals fetch returns nothing must keep
    /// the queued UUID so another drain entry can retry within 90s. Clearing
    /// before `startLiveActivity` ate the Shortcut on cold launch (#1222).
    @Test func `failed Track keeps the queued shortcut for retry`() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Permanent blocker path clears immediately — covered elsewhere.
            return
        }

        let dataLoader = MockDataLoader(testName: name)
        let app = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let regionID = app.regionsService.currentRegion?.regionIdentifier ?? pugetSoundRegionIdentifier
        let bookmark = Bookmark(
            name: "Route 49",
            regionIdentifier: regionID,
            arrivalDeparture: arrivalDep
        )
        app.userDataStore.add(bookmark, to: nil)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals_and_departures_empty.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") == true
        }

        // Write the queue without posting `.didStore` — that would race a second
        // drain via Application's observer while this test also calls consume.
        app.userDefaults.set(bookmark.id.uuidString, forKey: LiveActivityShortcutRequest.userDefaultsKey)
        app.userDefaults.set(Date().timeIntervalSince1970, forKey: LiveActivityShortcutRequest.storedAtKey)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: app.userDefaults) == bookmark.id)

        app.consumePendingLiveActivityShortcut()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(
            LiveActivityShortcutRequest.peek(userDefaults: app.userDefaults) == bookmark.id,
            "Transient Track failure must leave the shortcut queued for retry"
        )
    }
}
