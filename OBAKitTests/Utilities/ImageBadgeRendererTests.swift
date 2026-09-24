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

@MainActor
@Suite(.serialized)
final class ImageBadgeRendererTests {
    
    @Test func `Initialization applies explicit badgeSize`() {
        let renderer = ImageBadgeRenderer(fillColor: .red, backgroundColor: .blue, badgeSize: 64.0)
        #expect(renderer.badgeSize == 64.0)
    }

    @Test func `Default badge size is 128`() {
        let renderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: .black)
        #expect(renderer.badgeSize == 128.0)
    }

    @Test func `Rendering composites the image and background color`() throws {
        let badgeSize: CGFloat = 48.0
        let renderer = ImageBadgeRenderer(fillColor: .red, backgroundColor: .blue, badgeSize: badgeSize)
        
        // Generate a 10x10 solid image
        let frame = CGRect(origin: .zero, size: CGSize(width: 10, height: 10))
        let uiRenderer = UIGraphicsImageRenderer(bounds: frame)
        let dummyImage = uiRenderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(frame)
        }
        
        let badgedImage = renderer.drawImageOnRoundedRect(dummyImage)
        
        // The output image should match the badgeSize (48x48)
        #expect(badgedImage.size.width == badgeSize)
        #expect(badgedImage.size.height == badgeSize)
        
        // Verify it isn't an empty or blank image by comparing PNG data.
        // A blank/transparent 48x48 image will have a very small pngData signature.
        // A drawn rounded rect with a templated image in it will contain more pixel data.
        let blankImage = UIGraphicsImageRenderer(size: CGSize(width: badgeSize, height: badgeSize)).image { _ in }
        
        let badgedData = try #require(badgedImage.pngData())
        let blankData = try #require(blankImage.pngData())
        
        #expect(badgedData.count > blankData.count, "The badged image should contain composite pixel data, not just blank bounds")
        #expect(badgedData != blankData)
    }
}
