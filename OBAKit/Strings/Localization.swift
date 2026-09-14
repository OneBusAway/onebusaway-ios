//
//  Localization.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

fileprivate class Localization: NSObject {}

internal nonisolated func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: Localization.self), value: value, comment: comment)
}

/// A `Localizable.stringsdict` count. `String(format:)` without a locale resolves
/// `%#@count@` against the root plural rule, so only `one` and `other` are ever
/// reachable — a Polish rider hears the `other` form at 5 instead of `many`.
/// `bundle` is injectable so a test can load a language the host does not prefer.
enum CountPlural {
    static func format(
        _ key: String,
        value: String,
        comment: String,
        count: Int,
        locale: Locale = .current,
        bundle: Bundle = Bundle(for: Localization.self)
    ) -> String {
        let format = bundle.localizedString(forKey: key, value: value, table: nil)
        return String(format: format, locale: locale, count)
    }
}
