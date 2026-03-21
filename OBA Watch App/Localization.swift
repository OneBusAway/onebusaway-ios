//
//  Localization.swift
//  OBA Watch App
//
//  Created by Trae on 2024-10-25.
//

import Foundation

/// Localizes a string using the main bundle.
/// - Parameters:
///   - key: The key for the string.
///   - value: The default value to use if the key is not found.
///   - comment: A comment for the localizer.
/// - Returns: The localized string.
func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, value: value, comment: comment)
}
