//
//  LiveActivityShortcutRequestTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct LiveActivityShortcutRequestTests {

    /// Isolated suite plus teardown. A `deinit` cannot touch `UserDefaults`
    /// (non-Sendable) under the test target's isolation.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "live-activity-shortcut-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        body(userDefaults)
    }

    private func withDefaults(_ body: (UserDefaults) async -> Void) async {
        let suiteName = "live-activity-shortcut-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        await body(userDefaults)
    }

    /// `openAppWhenRun` brings the app forward *before* `perform()` stores.
    /// Lifecycle hooks have already peeked an empty queue. `store` must post
    /// so a warm app can select Bookmarks after the write.
    @Test func `Store posts so a warm app can drain after perform`() async {
        await withDefaults { userDefaults in
            await confirmation("didStore") { confirm in
                let token = NotificationCenter.default.addObserver(
                    forName: .liveActivityShortcutRequestDidStore,
                    object: nil,
                    queue: nil
                ) { _ in
                    confirm()
                }
                defer { NotificationCenter.default.removeObserver(token) }
                LiveActivityShortcutRequest.store(UUID(), userDefaults: userDefaults)
            }
        }
    }

    @Test func `Peek does not clear the stored id`() {
        withDefaults { userDefaults in
            let id = UUID()
            LiveActivityShortcutRequest.store(id, userDefaults: userDefaults)

            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == id)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == id)
        }
    }

    @Test func `Clear drops a still-valid request`() {
        withDefaults { userDefaults in
            let id = UUID()
            LiveActivityShortcutRequest.store(id, userDefaults: userDefaults)
            LiveActivityShortcutRequest.clear(userDefaults)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
        }
    }

    /// Timestamp present, UUID string garbage. Without the timestamp this
    /// is the same as the legacy-id test — `peek` clears at the first guard
    /// and never reaches `UUID.init`. Drop the UUID-parsing guard and this
    /// fails because a still-fresh timestamp plus a leftover string would
    /// otherwise peek as a request.
    @Test func `Garbage stored value is treated as empty`() {
        withDefaults { userDefaults in
            userDefaults.set("not-a-uuid", forKey: LiveActivityShortcutRequest.userDefaultsKey)
            userDefaults.set(Date().timeIntervalSince1970, forKey: LiveActivityShortcutRequest.storedAtKey)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
            #expect(userDefaults.string(forKey: LiveActivityShortcutRequest.userDefaultsKey) == nil)
            #expect(userDefaults.object(forKey: LiveActivityShortcutRequest.storedAtKey) == nil)
        }
    }

    /// A request without a timestamp is treated as expired so a leftover id
    /// cannot force the Bookmarks tab on every launch.
    @Test func `Legacy id without a timestamp is treated as empty`() {
        withDefaults { userDefaults in
            userDefaults.set(UUID().uuidString, forKey: LiveActivityShortcutRequest.userDefaultsKey)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
            #expect(userDefaults.string(forKey: LiveActivityShortcutRequest.userDefaultsKey) == nil)
        }
    }

    /// Drop the expiry check and a request queued hours earlier still peeks.
    @Test func `Peek returns nil and clears after the expiration window`() {
        withDefaults { userDefaults in
            let id = UUID()
            let storedAt = Date(timeIntervalSince1970: 0)
            LiveActivityShortcutRequest.store(id, userDefaults: userDefaults, now: storedAt)

            let stillFresh = storedAt.addingTimeInterval(LiveActivityShortcutRequest.expiration)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults, now: stillFresh) == id)

            let expired = storedAt.addingTimeInterval(LiveActivityShortcutRequest.expiration + 1)
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults, now: expired) == nil)
            #expect(userDefaults.string(forKey: LiveActivityShortcutRequest.userDefaultsKey) == nil)
            #expect(userDefaults.object(forKey: LiveActivityShortcutRequest.storedAtKey) == nil)
        }
    }

    /// `peek` is called from become-active, Bookmarks `viewWillAppear`, and
    /// the 30s arrivals tick. An empty suite must not `removeObject`.
    @Test func `Peek on an empty suite does not write`() {
        withDefaults { userDefaults in
            #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
            #expect(userDefaults.object(forKey: LiveActivityShortcutRequest.userDefaultsKey) == nil)
            #expect(userDefaults.object(forKey: LiveActivityShortcutRequest.storedAtKey) == nil)
        }
    }
}
