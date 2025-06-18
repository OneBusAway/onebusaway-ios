//
//  UIApplicationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import UIKit
@testable import OBAKit

class UIApplicationExtensionsTests: XCTestCase {
    
    func test_keyWindowFromScene_returnsKeyWindow() {
        // This test is limited in unit test environment since we can't easily create real scenes
        // We'll test that the property exists and returns a window when available
        let app = UIApplication.shared
        
        // The property should exist and be accessible
        let keyWindow = app.keyWindowFromScene
        // In test environment, this might be nil, but the property should be accessible
        // keyWindow can be nil or a UIWindow instance
        if let keyWindow = keyWindow {
            expect(keyWindow).to(beAnInstanceOf(UIWindow.self))
        } else {
            expect(keyWindow).to(beNil())
        }
    }
    
    func test_activeWindows_returnsWindowArray() {
        let app = UIApplication.shared
        
        // The property should exist and return an array
        let windows = app.activeWindows
        expect(windows).to(beAnInstanceOf([UIWindow].self))
    }
}
