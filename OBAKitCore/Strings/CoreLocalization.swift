//
//  CoreLocalization.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 1/2/20.
//

import Foundation

fileprivate class CoreLocalization: NSObject {}

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: CoreLocalization.self), value: value, comment: comment)
}
