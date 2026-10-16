//
//  CoreLocalization.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension Bundle {
    /// OBAKitCore's resources: its string tables and privacy manifest. A package
    /// target's resources live in a bundle of their own, so `Bundle(for:)` on a
    /// Core type finds the code, not these. Tests reach this through
    /// `@testable import`.
    static var obaKitCore: Bundle { .module }
}

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: .module, value: value, comment: comment)
}
