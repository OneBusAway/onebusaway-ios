//
//  Localization.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension Bundle {
    /// OBAKit's resources: string tables, asset catalog, credits and privacy
    /// manifest. A package target's resources live in a bundle of their own, so
    /// `Bundle(for:)` on an OBAKit type finds the code, not these. Tests reach
    /// this through `@testable import`.
    nonisolated static var obaKit: Bundle { .module }
}

internal nonisolated func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: .module, value: value, comment: comment)
}

/// Formats a `Localizable.stringsdict` count with an explicit locale.
///
/// `String(format:)` without a locale resolves `%#@count@` against the root
/// plural rule, so only `one` and `other` are ever reachable — a Polish rider
/// hears the `other` form at 5 instead of `many`.
///
/// Call sites must pass an already-localized format from `OBALoc(...)` so
/// `scripts/extract_strings` (`genstrings -s OBALoc`) still sees the key.
/// Optional `locale` is for tests that pin a language the host does not prefer.
enum CountPlural {
    static func format(
        _ format: String,
        count: Int,
        locale: Locale = .current
    ) -> String {
        String(format: format, locale: locale, count)
    }
}
