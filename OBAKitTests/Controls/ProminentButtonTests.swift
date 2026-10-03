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
        
        button.layoutSubviews()
        let highlightLayer = button.layer.sublayers?.last
        #expect(highlightLayer?.backgroundColor == newColor.cgColor)
    }

    @Test func testLayoutSubviewsAddsHighlightLayer() {
        let button = ProminentButton(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        
        button.setNeedsLayout()
        button.layoutIfNeeded()
        
        let highlightLayer = button.layer.sublayers?.last
        #expect(highlightLayer?.backgroundColor == button.prominentColor.cgColor)
        #expect(highlightLayer?.cornerRadius == ThemeMetrics.compactCornerRadius)
    }
}
