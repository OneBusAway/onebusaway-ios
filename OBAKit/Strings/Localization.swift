//
//  Localization.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/2/20.
//

import Foundation

fileprivate class Localization: NSObject {}

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: Localization.self), value: value, comment: comment)
}
