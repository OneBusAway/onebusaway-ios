//
//  WatchLocalization.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

fileprivate class OBAKitWatchLocalization: NSObject {}

/// Looks a string up in this framework's bundle. Same shape as OBAKitCore's
/// and OBAWidget's helpers, which are `internal` to their modules.
internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: Bundle(for: OBAKitWatchLocalization.self), value: value, comment: comment)
}
