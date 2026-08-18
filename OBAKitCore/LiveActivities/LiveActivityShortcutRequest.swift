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

    public static func store(_ bookmarkID: UUID, userDefaults: UserDefaults) {
        userDefaults.set(bookmarkID.uuidString, forKey: userDefaultsKey)
    }

    /// The pending bookmark id, if any. Does not clear it.
    public static func peek(userDefaults: UserDefaults) -> UUID? {
        userDefaults.string(forKey: userDefaultsKey).flatMap(UUID.init(uuidString:))
    }

    /// Returns the pending bookmark id and clears it. `nil` if nothing was stored
    /// or the stored value is not a UUID.
    public static func take(userDefaults: UserDefaults) -> UUID? {
        let id = peek(userDefaults: userDefaults)
        userDefaults.removeObject(forKey: userDefaultsKey)
        return id
    }
}
