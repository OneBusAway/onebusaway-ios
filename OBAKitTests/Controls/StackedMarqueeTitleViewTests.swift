//
//  StackedMarqueeTitleViewTests.swift
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
import MarqueeLabel
@testable import OBAKit
@testable import OBAKitCore

class StackedMarqueeTitleViewTests: XCTestCase {
    
    var titleView: StackedMarqueeTitleView!
    let testWidth: CGFloat = 200.0
    
    override func setUp() {
        super.setUp()
        titleView = StackedMarqueeTitleView(width: testWidth)
    }
    
    func test_init_createsLabels() {
        expect(self.titleView).toNot(beNil())
        expect(self.titleView.topLabel).to(beAnInstanceOf(MarqueeLabel.self))
        expect(self.titleView.bottomLabel).to(beAnInstanceOf(MarqueeLabel.self))
    }
    
    func test_init_addsLabelsAsSubviews() {
        expect(self.titleView.subviews.count) == 2
        expect(self.titleView.subviews).to(contain(self.titleView.topLabel))
        expect(self.titleView.subviews).to(contain(self.titleView.bottomLabel))
    }
    
    func test_topLabel_configuration() {
        let topLabel = titleView.topLabel
        
        expect(topLabel.frame.width) == testWidth
        expect(topLabel.font).toNot(beNil())
        expect(topLabel.adjustsFontForContentSizeCategory) == true
        expect(topLabel.textAlignment) == .center
        expect(topLabel.adjustsFontSizeToFitWidth) == true
        expect(topLabel.trailingBuffer) == ThemeMetrics.padding
        expect(topLabel.fadeLength) == ThemeMetrics.padding
    }
    
    func test_bottomLabel_configuration() {
        let bottomLabel = titleView.bottomLabel
        
        expect(bottomLabel.frame.width) == testWidth
        expect(bottomLabel.font).toNot(beNil())
        expect(bottomLabel.adjustsFontForContentSizeCategory) == true
        expect(bottomLabel.textAlignment) == .center
        expect(bottomLabel.adjustsFontSizeToFitWidth) == true
        expect(bottomLabel.trailingBuffer) == ThemeMetrics.padding
        expect(bottomLabel.fadeLength) == ThemeMetrics.padding
    }
    
    func test_labels_positioning() {
        // Bottom label should be positioned below top label
        expect(self.titleView.bottomLabel.frame.origin.y) == self.titleView.topLabel.frame.maxY
        expect(self.titleView.topLabel.frame.origin.y) == 0
    }
    
    func test_frame_sizing() {
        let expectedHeight = titleView.topLabel.frame.height + titleView.bottomLabel.frame.height
        expect(self.titleView.frame.width) == testWidth
        expect(self.titleView.frame.height) == expectedHeight
    }
    
    func test_initWithCoder_fatalError() {
        expect {
            _ = StackedMarqueeTitleView(coder: NSCoder())
        }.to(throwAssertion())
    }
}
