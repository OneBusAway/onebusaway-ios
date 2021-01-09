//
//  Localization.swift
//  TodayView
//
//  Created by Alan Chu on 12/30/20.
//

import Foundation

fileprivate class TodayViewLocalization: NSObject {}

internal func OBALoc(_ key: String, value: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: nil, bundle: Bundle(for: TodayViewLocalization.self), value: value, comment: comment)
}
