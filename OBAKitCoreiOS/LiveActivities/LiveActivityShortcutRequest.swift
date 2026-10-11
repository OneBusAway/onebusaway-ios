//
//  LiveActivityShortcutRequest.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public extension Notification.Name {
    /// Posted after `store` writes a still-valid request. `openAppWhenRun`
    /// brings the app forward *before* `perform()`, so lifecycle hooks have
    /// already peeked an empty queue. The app observes this to start the
    /// Live Activity after the write.
    static let liveActivityShortcutRequestDidStore = Notification.Name("LiveActivityShortcutRequest.didStore")
}

/// Queues a bookmark Live Activity request from an App Intent so the main app
/// can start it after `openAppWhenRun` brings the process up. ActivityKit
/// `request` lives on the in-app Track path (`BookmarkActions.startLiveActivity`);
/// the intent must not capture an `Activity` across a `Task` hop. See #1222.
public enum LiveActivityShortcutRequest {

    /// UserDefaults key for the pending bookmark UUID. Dotted is fine: this is
    /// not observed via `@AppStorage`.
    public static let userDefaultsKey = "LiveActivityShortcut.pendingBookmarkID"

    /// When the UUID was stored. Peek drops the request after `expiration`.
    public static let storedAtKey = "LiveActivityShortcut.pendingBookmarkStoredAt"

    /// How long a queued request may wait for a successful Live Activity start
    /// (arrivals fetch + ActivityKit). Short enough that a stuck request cannot
    /// retry forever across launches; long enough for a cold start to load the
    /// bookmark's stop.
    public static let expiration: TimeInterval = 90

    public static func store(_ bookmarkID: UUID, userDefaults: UserDefaults, now: Date = Date()) {
        userDefaults.set(bookmarkID.uuidString, forKey: userDefaultsKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: storedAtKey)
        NotificationCenter.default.post(name: .liveActivityShortcutRequestDidStore, object: nil)
    }

    /// The pending bookmark id, if any and not expired. Does not clear a
    /// still-valid request. Expired or garbage values are removed.
    public static func peek(userDefaults: UserDefaults, now: Date = Date()) -> UUID? {
        let rawID = userDefaults.string(forKey: userDefaultsKey)
        let storedAtObject = userDefaults.object(forKey: storedAtKey)
        if rawID == nil && storedAtObject == nil {
            return nil
        }

        guard let storedAt = storedAtObject as? TimeInterval else {
            clear(userDefaults)
            return nil
        }
        if now.timeIntervalSince1970 - storedAt > expiration {
            clear(userDefaults)
            return nil
        }
        guard let id = userDefaults.string(forKey: userDefaultsKey).flatMap(UUID.init(uuidString:)) else {
            clear(userDefaults)
            return nil
        }
        return id
    }

    public static func clear(_ userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: userDefaultsKey)
        userDefaults.removeObject(forKey: storedAtKey)
    }
}
