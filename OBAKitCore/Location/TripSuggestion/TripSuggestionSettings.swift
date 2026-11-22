//
//  TripSuggestionSettings.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The rider's Trip Suggestions preference, set from the Map sheet.
public enum TripSuggestionSettings {
    public static let enabledKey = "OBATripSuggestionsEnabled"

    /// On unless the rider has turned it off.
    public static func isEnabled(userDefaults: UserDefaults) -> Bool {
        guard userDefaults.object(forKey: enabledKey) != nil else { return true }
        return userDefaults.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool, userDefaults: UserDefaults) {
        userDefaults.set(enabled, forKey: enabledKey)
    }
}
