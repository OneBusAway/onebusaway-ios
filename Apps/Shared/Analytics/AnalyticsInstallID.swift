//
//  AnalyticsInstallID.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A random, anonymous, per-install identifier for analytics backends that
/// derive their own "visitor"/session ID from client IP + User-Agent (e.g.
/// Umami). Those backends mint a new visitor on every IP change (wifi ↔
/// cellular) unless the event payload supplies a stable `id`; this type is
/// that `id`.
///
/// Deliberately NOT derived from any device identifier (no
/// `identifierForVendor`, no IDFA/`ASIdentifierManager`): the value is
/// generated locally with `UUID()` and persisted in `UserDefaults`, so a
/// reinstall mints a fresh ID — the same per-install semantics Google
/// Analytics uses, and it carries no App Tracking Transparency implications.
enum AnalyticsInstallID {
    private static let userDefaultsKey = "AnalyticsInstallIDUserDefaultsKey"

    /// Returns the persisted install ID, generating and storing one on first
    /// call. Stable across calls (and across app launches) for a given
    /// `userDefaults` store.
    static func persisted(userDefaults: UserDefaults = .standard) -> String {
        if let existing = userDefaults.string(forKey: userDefaultsKey) {
            return existing
        }

        let newID = UUID().uuidString
        userDefaults.set(newID, forKey: userDefaultsKey)
        return newID
    }
}
