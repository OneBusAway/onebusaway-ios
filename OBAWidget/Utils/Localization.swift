//
//  Localization.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-16.
//

import Foundation

fileprivate class OBAWidgetLocalization: NSObject {}

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: OBAWidgetLocalization.self), value: value, comment: comment)
}
