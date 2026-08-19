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

    private func defaults() -> UserDefaults {
        let suite = "live-activity-shortcut-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    /// `take` must clear: if it only peeked, a later foreground would start
    /// the same activity again. Revert the removeObject and this fails.
    @Test func `Take returns the stored id and clears it`() {
        let userDefaults = defaults()
        let id = UUID()

        LiveActivityShortcutRequest.store(id, userDefaults: userDefaults)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == id)

        #expect(LiveActivityShortcutRequest.take(userDefaults: userDefaults) == id)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
        #expect(LiveActivityShortcutRequest.take(userDefaults: userDefaults) == nil)
    }

    @Test func `Peek does not clear the stored id`() {
        let userDefaults = defaults()
        let id = UUID()
        LiveActivityShortcutRequest.store(id, userDefaults: userDefaults)

        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == id)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == id)
    }

    @Test func `Garbage stored value is treated as empty`() {
        let userDefaults = defaults()
        userDefaults.set("not-a-uuid", forKey: LiveActivityShortcutRequest.userDefaultsKey)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
        #expect(LiveActivityShortcutRequest.take(userDefaults: userDefaults) == nil)
    }

    /// A request without a timestamp is treated as expired so a leftover id
    /// cannot force the Bookmarks tab on every launch.
    @Test func `Legacy id without a timestamp is treated as empty`() {
        let userDefaults = defaults()
        userDefaults.set(UUID().uuidString, forKey: LiveActivityShortcutRequest.userDefaultsKey)
        #expect(LiveActivityShortcutRequest.peek(userDefaults: userDefaults) == nil)
        #expect(userDefaults.string(forKey: LiveActivityShortcutRequest.userDefaultsKey) == nil)
    }

    /// Drop the expiry check and a request queued hours earlier still peeks.
    @Test func `Peek returns nil and clears after the expiration window`() {
        let userDefaults = defaults()
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
