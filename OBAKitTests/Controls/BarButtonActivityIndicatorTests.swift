//
//  BarButtonActivityIndicatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Testing
import UIKit
@testable import OBAKit

@MainActor
class BarButtonActivityIndicatorTests: XCTestCase {
    
    func test_UIActivityIndicatorView_asNavigationItem() {
        let barButtonItem = UIActivityIndicatorView.asNavigationItem()
        
        #expect(type(of: barButtonItem) == UIBarButtonItem.self)
        #expect(barButtonItem.customView.map { type(of: $0) == UIActivityIndicatorView.self } == true)
        
        let activityIndicator = barButtonItem.customView as! UIActivityIndicatorView
        #expect(activityIndicator.style == .medium)
        #expect(activityIndicator.isAnimating == true)
    }
}
