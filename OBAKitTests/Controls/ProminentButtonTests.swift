//
//  ProminentButtonTests.swift
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
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class ProminentButtonTests {
    
    @Test func testInitialization() {
        let button = ProminentButton(frame: .zero)
        
        let expectedColor = UIColor(white: 0.5, alpha: 0.1)
        #expect(button.prominentColor == expectedColor)
    }

    @Test func testProminentColorUpdate() {
        let button = ProminentButton(frame: .zero)
        let newColor = UIColor.red
        
        button.prominentColor = newColor
        #expect(button.prominentColor == newColor)
        
        // Assert the sublayer color was updated (highlightLayer is private, but its effect should reflect on layout)
        // Note: we can't directly check the private highlightLayer, but we can verify the property updates correctly.
    }

    @Test func testLayoutSubviewsAddsHighlightLayer() {
        let button = ProminentButton(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        
        let initialLayerCount = button.layer.sublayers?.count ?? 0
        
        button.layoutSubviews()
        
        let newLayerCount = button.layer.sublayers?.count ?? 0
        #expect(newLayerCount == initialLayerCount + 1, "layoutSubviews should add the highlightLayer")
    }
}
