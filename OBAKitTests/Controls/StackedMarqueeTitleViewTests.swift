//
//  StackedMarqueeTitleViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
import MarqueeLabel
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class StackedMarqueeTitleViewTests {
    
    var titleView: StackedMarqueeTitleView!
    let testWidth: CGFloat = 200.0
    
    init() {
        titleView = StackedMarqueeTitleView(width: testWidth)
    }
    
    @Test func `Init creates labels`() {
        #expect(self.titleView != nil)
        #expect(type(of: self.titleView.topLabel) == MarqueeLabel.self)
        #expect(type(of: self.titleView.bottomLabel) == MarqueeLabel.self)
    }
    
    @Test func `Init adds labels as subviews`() {
        #expect(self.titleView.subviews.count == 2)
        #expect(self.titleView.subviews.contains(self.titleView.topLabel))
        #expect(self.titleView.subviews.contains(self.titleView.bottomLabel))
    }
    
    @Test func `Top label configuration`() {
        let topLabel = titleView.topLabel
        
        #expect(topLabel.frame.width == testWidth)
        #expect(topLabel.font != nil)
        #expect(topLabel.adjustsFontForContentSizeCategory == true)
        #expect(topLabel.textAlignment == .center)
        #expect(topLabel.adjustsFontSizeToFitWidth == true)
        #expect(topLabel.trailingBuffer == ThemeMetrics.padding)
        #expect(topLabel.fadeLength == ThemeMetrics.padding)
    }
    
    @Test func `Bottom label configuration`() {
        let bottomLabel = titleView.bottomLabel
        
        #expect(bottomLabel.frame.width == testWidth)
        #expect(bottomLabel.font != nil)
        #expect(bottomLabel.adjustsFontForContentSizeCategory == true)
        #expect(bottomLabel.textAlignment == .center)
        #expect(bottomLabel.adjustsFontSizeToFitWidth == true)
        #expect(bottomLabel.trailingBuffer == ThemeMetrics.padding)
        #expect(bottomLabel.fadeLength == ThemeMetrics.padding)
    }
    
    @Test func `Labels positioning`() {
        // Bottom label should be positioned below top label
        #expect(self.titleView.bottomLabel.frame.origin.y == self.titleView.topLabel.frame.maxY)
        #expect(self.titleView.topLabel.frame.origin.y == 0)
    }
    
    @Test func `Frame sizing`() {
        let expectedHeight = titleView.topLabel.frame.height + titleView.bottomLabel.frame.height
        #expect(self.titleView.frame.width == testWidth)
        #expect(self.titleView.frame.height == expectedHeight)
    }
}
