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
        #expect(app.viewRouter.rootController == nil)
    }
}
