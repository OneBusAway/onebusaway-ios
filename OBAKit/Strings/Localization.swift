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

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: Localization.self), value: value, comment: comment)
}
