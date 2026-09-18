//
//  ImageBadgeRendererTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKitCore

@Suite(.serialized)
final class ImageBadgeRendererTests {
    
    @Test func `Initialization sets properties correctly`() {
        let renderer = ImageBadgeRenderer(fillColor: .red, backgroundColor: .blue, badgeSize: 64.0)
        #expect(renderer.badgeSize == 64.0)
    }

    @Test func `Default badge size is 128`() {
        let renderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: .black)
        #expect(renderer.badgeSize == 128.0)
    }

    @Test func `Rendering produces a UIImage of expected size`() {
        let renderer = ImageBadgeRenderer(fillColor: .red, backgroundColor: .blue, badgeSize: 48.0)
        
        // Generate a 10x10 dummy image
        let frame = CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
        let uiRenderer = UIGraphicsImageRenderer(bounds: frame)
        let dummyImage = uiRenderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(frame)
        }
        
        let badgedImage = renderer.drawImageOnRoundedRect(dummyImage)
        
        // The output image should match the badgeSize (48x48)
        #expect(badgedImage.size.width == 48.0)
        #expect(badgedImage.size.height == 48.0)
    }
}
