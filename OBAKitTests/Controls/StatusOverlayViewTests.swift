//
//  StatusOverlayViewTests.swift
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
@testable import OBAKitCore

class StatusOverlayViewTests: XCTestCase {
    
    var statusOverlayView: StatusOverlayView!
    
    override func setUp() {
        super.setUp()
        statusOverlayView = StatusOverlayView(frame: .zero)
    }
    
    func test_init_setsCornerRadius() {
        expect(self.statusOverlayView.layer.cornerRadius) == ThemeMetrics.padding
    }
    
    func test_text_getterAndSetter() {
        let testText = "Test Status Message"
        statusOverlayView.text = testText
        
        expect(self.statusOverlayView.text) == testText
    }
    
    func test_text_nilValue() {
        statusOverlayView.text = nil
        
        expect(self.statusOverlayView.text).to(beNil())
    }
    
    func test_showOverlay_withoutAnimation() {
        let message = "Test Message"
        statusOverlayView.showOverlay(message: message, animated: false)
        
        expect(self.statusOverlayView.text) == message
        
        // Access the status overlay through the subviews
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        expect(statusOverlay?.isHidden) == false
        expect(statusOverlay?.alpha) == 1.0
    }
    
    func test_hideOverlay_withoutAnimation() {
        // First show the overlay
        statusOverlayView.showOverlay(message: "Test", animated: false)
        
        // Then hide it
        statusOverlayView.hideOverlay(animated: false)
        
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        expect(statusOverlay?.isHidden) == true
        expect(statusOverlay?.alpha) == 0.0
    }
    
    func test_showOverlay_withAnimation() {
        let message = "Animated Test Message"
        statusOverlayView.showOverlay(message: message, animated: true)
        
        expect(self.statusOverlayView.text) == message
        
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        expect(statusOverlay?.isHidden) == false
        // Alpha should start at 0 and animate to 1, but we can't easily test the animation state
    }
    
    func test_hideOverlay_withAnimation() {
        // First show the overlay without animation
        statusOverlayView.showOverlay(message: "Test", animated: false)
        
        // Then hide it with animation
        statusOverlayView.hideOverlay(animated: true)
        
        // The animation should start, but we can't easily test the final state in unit tests
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        expect(statusOverlay).toNot(beNil())
    }
    
    func test_subviewStructure() {
        // Test that the view has the expected subview structure
        expect(self.statusOverlayView.subviews.count) == 1
        
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        expect(statusOverlay).toNot(beNil())
        expect(statusOverlay?.contentView.subviews.count) == 1
        
        let statusLabel = statusOverlay?.contentView.subviews.first as? UILabel
        expect(statusLabel).toNot(beNil())
        expect(statusLabel?.textAlignment) == .center
    }
    
    func test_statusOverlay_properties() {
        let statusOverlay = self.statusOverlayView.subviews.first as? UIVisualEffectView
        
        expect(statusOverlay?.backgroundColor) == UIColor.white.withAlphaComponent(0.60)
        expect(statusOverlay?.clipsToBounds) == true
        expect(statusOverlay?.effect).to(beAnInstanceOf(UIBlurEffect.self))
    }
}
