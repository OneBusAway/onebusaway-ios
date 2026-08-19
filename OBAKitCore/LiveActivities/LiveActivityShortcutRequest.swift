//
//  LiveActivityShortcutRequest.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Queues a bookmark Live Activity request from an App Intent so the main app
/// can start it after `openAppWhenRun` brings the process up. ActivityKit
/// `request` lives on the in-app start path (`BookmarksViewController`); the
/// intent must not capture an `Activity` across a `Task` hop. See #1222.
public enum LiveActivityShortcutRequest {

    /// UserDefaults key for the pending bookmark UUID. Dotted is fine: this is
    /// not observed via `@AppStorage`.
    public static let userDefaultsKey = "LiveActivityShortcut.pendingBookmarkID"

    /// When the UUID was stored. Peek/take drop the request after `expiration`.
    public static let storedAtKey = "LiveActivityShortcut.pendingBookmarkStoredAt"

    /// How long a queued request may hijack the Bookmarks tab. Short enough
    /// that a failed arrivals fetch cannot force the tab on every launch;
    /// long enough for a cold start to load the bookmark's stop.
    public static let expiration: TimeInterval = 90

    public static func store(_ bookmarkID: UUID, userDefaults: UserDefaults, now: Date = Date()) {
        userDefaults.set(bookmarkID.uuidString, forKey: userDefaultsKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: storedAtKey)
    }

    /// The pending bookmark id, if any and not expired. Does not clear a
    /// still-valid request. Expired or garbage values are removed.
    public static func peek(userDefaults: UserDefaults, now: Date = Date()) -> UUID? {
        guard let storedAt = userDefaults.object(forKey: storedAtKey) as? TimeInterval else {
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

    /// Returns the pending bookmark id and clears it. `nil` if nothing was stored,
    /// the stored value is not a UUID, or the request has expired.
    public static func take(userDefaults: UserDefaults, now: Date = Date()) -> UUID? {
        let id = peek(userDefaults: userDefaults, now: now)
        clear(userDefaults)
        return id
    }

    public static func clear(_ userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: userDefaultsKey)
        userDefaults.removeObject(forKey: storedAtKey)
    }
}
