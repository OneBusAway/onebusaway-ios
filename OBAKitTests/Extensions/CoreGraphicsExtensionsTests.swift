//
//  CoreGraphicsExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import CoreGraphics
import UIKit
@testable import OBAKit
@testable import OBAKitCore

class CoreGraphicsExtensionsTests: XCTestCase {
    
    func test_CGContext_pushPop() {
        // Create a simple graphics context for testing
        let size = CGSize(width: 100, height: 100)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        expect(context).toNot(beNil())
        
        guard let ctx = context else { return }
        
        // Test that pushPop doesn't crash and preserves state
        // We can't directly test color state, but we can test transform state
        let initialTransform = ctx.ctm
        
        // Use pushPop to temporarily change state
        ctx.pushPop {
            ctx.translateBy(x: 10, y: 10)
            let modifiedTransform = ctx.ctm
            expect(modifiedTransform.tx) == 10.0
            expect(modifiedTransform.ty) == 10.0
        }
        
        // Verify state was restored
        let restoredTransform = ctx.ctm
        expect(restoredTransform.tx) == initialTransform.tx
        expect(restoredTransform.ty) == initialTransform.ty
    }
    
    func test_CGContext_pushPop_nested() {
        let size = CGSize(width: 100, height: 100)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let ctx = context else { return }
        
        // Test nested pushPop calls with transform state
        let initialTransform = ctx.ctm
        
        ctx.pushPop {
            ctx.translateBy(x: 5, y: 5)
            
            ctx.pushPop {
                ctx.translateBy(x: 5, y: 5)
                let nestedTransform = ctx.ctm
                expect(nestedTransform.tx) == 10.0 // 5 + 5
                expect(nestedTransform.ty) == 10.0 // 5 + 5
            }
            
            // Inner scope restored
            let middleTransform = ctx.ctm
            expect(middleTransform.tx) == 5.0
            expect(middleTransform.ty) == 5.0
        }
        
        // All state restored
        let finalTransform = ctx.ctm
        expect(finalTransform.tx) == initialTransform.tx
        expect(finalTransform.ty) == initialTransform.ty
    }
    
    func test_CGContext_pushPop_doesNotCrash() {
        let size = CGSize(width: 100, height: 100)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let ctx = context else { return }
        
        // Test that pushPop doesn't crash with empty closure
        ctx.pushPop {
            // Empty closure
        }
        
        expect(true).to(beTrue()) // Test that it doesn't crash
    }
}
