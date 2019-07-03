//
//  Analytics.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import Foundation

@objc(OBAAnalytics)
public protocol Analytics: NSObjectProtocol {
    func logEvent(name: String, parameters: [String: Any])
}
