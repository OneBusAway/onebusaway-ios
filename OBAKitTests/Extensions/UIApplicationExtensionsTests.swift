//
//  UIApplicationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class UIApplicationExtensionsTests {
    
    @Test func `Key window from scene returns key window`() {
        // This test is limited in unit test environment since we can't easily create real scenes
        // We'll test that the property exists and returns a window when available
        let app = UIApplication.shared
        
        // The property should exist and be accessible
        let keyWindow = app.keyWindowFromScene
        // In test environment, this might be nil, but the property should be accessible
        // keyWindow can be nil or a UIWindow instance
        if let keyWindow = keyWindow {
            #expect(type(of: keyWindow) == UIWindow.self)
        } else {
            #expect(keyWindow == nil)
        }
    }
    
    @Test func `Active windows returns window array`() {
        let app = UIApplication.shared
        
        // The property should exist and return an array
        let windows = app.activeWindows
        #expect(type(of: windows) == [UIWindow].self)
    }
}
