//
//  UIImageShadowTests.swift
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
import CoreGraphics
@testable import OBAKit

class UIImageShadowTests: XCTestCase {
    
    func test_Shadow_struct() {
        let offset = CGSize(width: 1, height: 2)
        let blur: CGFloat = 5.0
        let color = UIColor.black
        
        let shadow = Shadow(offset: offset, blur: blur, color: color)
        
        expect(shadow.offset) == offset
        expect(shadow.blur) == blur
        expect(shadow.color) == color
    }
    
    func test_UIImage_resizableShadowImage_basic() {
        let sideLength: CGFloat = 50.0
        let cornerRadius: CGFloat = 10.0
        let shadow = Shadow(offset: .zero, blur: 5.0, color: .black)
        
        let shadowImage = UIImage.resizableShadowImage(
            withSideLength: sideLength,
            cornerRadius: cornerRadius,
            shadow: shadow,
            shouldDrawCapInsets: false
        )
        
        expect(shadowImage).toNot(beNil())
        expect(shadowImage.size.width).to(beGreaterThan(0))
        expect(shadowImage.size.height).to(beGreaterThan(0))
        
        // Check that the image is resizable
        expect(shadowImage.capInsets.top).to(beGreaterThan(0))
        expect(shadowImage.capInsets.left).to(beGreaterThan(0))
        expect(shadowImage.capInsets.bottom).to(beGreaterThan(0))
        expect(shadowImage.capInsets.right).to(beGreaterThan(0))
        expect(shadowImage.resizingMode) == .tile
    }
    
    func test_UIImage_resizableShadowImage_withCapInsets() {
        let sideLength: CGFloat = 40.0
        let cornerRadius: CGFloat = 8.0
        let shadow = Shadow(offset: CGSize(width: 2, height: 2), blur: 3.0, color: .gray)
        
        let shadowImage = UIImage.resizableShadowImage(
            withSideLength: sideLength,
            cornerRadius: cornerRadius,
            shadow: shadow,
            shouldDrawCapInsets: true
        )
        
        expect(shadowImage).toNot(beNil())
        expect(shadowImage.size.width).to(beGreaterThan(0))
        expect(shadowImage.size.height).to(beGreaterThan(0))
        
        // With debug cap insets enabled, the image should still be created successfully
        expect(shadowImage.capInsets.top).to(beGreaterThan(0))
        expect(shadowImage.capInsets.left).to(beGreaterThan(0))
        expect(shadowImage.capInsets.bottom).to(beGreaterThan(0))
        expect(shadowImage.capInsets.right).to(beGreaterThan(0))
    }
    
    func test_UIImage_resizableShadowImage_differentParameters() {
        // Test with different parameters to ensure robustness
        let shadows = [
            Shadow(offset: .zero, blur: 0.0, color: .clear),
            Shadow(offset: CGSize(width: 5, height: -5), blur: 10.0, color: .red),
            Shadow(offset: CGSize(width: -3, height: 3), blur: 2.0, color: .blue)
        ]
        
        for shadow in shadows {
            let shadowImage = UIImage.resizableShadowImage(
                withSideLength: 30.0,
                cornerRadius: 5.0,
                shadow: shadow,
                shouldDrawCapInsets: false
            )
            
            expect(shadowImage).toNot(beNil())
            expect(shadowImage.size.width).to(beGreaterThan(0))
            expect(shadowImage.size.height).to(beGreaterThan(0))
        }
    }
    
    func test_UIImage_resizableShadowImage_zeroCornerRadius() {
        let sideLength: CGFloat = 60.0
        let cornerRadius: CGFloat = 0.0 // No rounded corners
        let shadow = Shadow(offset: CGSize(width: 1, height: 1), blur: 4.0, color: .black)
        
        let shadowImage = UIImage.resizableShadowImage(
            withSideLength: sideLength,
            cornerRadius: cornerRadius,
            shadow: shadow,
            shouldDrawCapInsets: false
        )
        
        expect(shadowImage).toNot(beNil())
        expect(shadowImage.size.width).to(beGreaterThan(0))
        expect(shadowImage.size.height).to(beGreaterThan(0))
        
        // Even with zero corner radius, cap insets should be set based on blur
        expect(shadowImage.capInsets.top) == shadow.blur
        expect(shadowImage.capInsets.left) == shadow.blur
        expect(shadowImage.capInsets.bottom) == shadow.blur
        expect(shadowImage.capInsets.right) == shadow.blur
    }
    
    func test_UIImage_resizableShadowImage_imageSizeCalculation() {
        let sideLength: CGFloat = 100.0
        let cornerRadius: CGFloat = 15.0
        let blur: CGFloat = 8.0
        let shadow = Shadow(offset: .zero, blur: blur, color: .black)
        
        let shadowImage = UIImage.resizableShadowImage(
            withSideLength: sideLength,
            cornerRadius: cornerRadius,
            shadow: shadow,
            shouldDrawCapInsets: false
        )
        
        // The image size should be sideLength + (blur * 2)
        let expectedSize = sideLength + (blur * 2.0)
        expect(shadowImage.size.width) == expectedSize
        expect(shadowImage.size.height) == expectedSize
        
        // Cap insets should be cornerRadius + blur
        let expectedCapInset = cornerRadius + blur
        expect(shadowImage.capInsets.top) == expectedCapInset
        expect(shadowImage.capInsets.left) == expectedCapInset
        expect(shadowImage.capInsets.bottom) == expectedCapInset
        expect(shadowImage.capInsets.right) == expectedCapInset
    }
}
