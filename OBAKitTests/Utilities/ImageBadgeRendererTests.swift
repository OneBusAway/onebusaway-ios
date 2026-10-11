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
        
        // Verify pixel colors to ensure the icon and background were composited.
        func color(at point: CGPoint, in image: UIImage) -> UIColor? {
            var pixel: [UInt8] = [0, 0, 0, 0]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            
            context.translateBy(x: -point.x, y: -point.y)
            UIGraphicsPushContext(context)
            image.draw(at: .zero)
            UIGraphicsPopContext()
            
            return UIColor(red: CGFloat(pixel[0]) / 255.0, green: CGFloat(pixel[1]) / 255.0, blue: CGFloat(pixel[2]) / 255.0, alpha: CGFloat(pixel[3]) / 255.0)
        }
        
        // The image is drawn at 75% of badgeSize (36x36) centered.
        // Center pixel (24, 24) should be the templated image fill color (.red).
        let centerColor = try #require(color(at: CGPoint(x: 24, y: 24), in: badgedImage))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        centerColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.9, "Center pixel should be red (fillColor)")
        #expect(b < 0.1, "Center pixel should not be blue")
        
        // A pixel near the edge (e.g. x: 4, y: 24) is outside the 36x36 icon (which starts at x=6), 
        // but inside the rounded rect background. It should be the background color (.blue).
        let edgeColor = try #require(color(at: CGPoint(x: 4, y: 24), in: badgedImage))
        edgeColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.1, "Edge pixel should not be red")
        #expect(b > 0.9, "Edge pixel should be blue (backgroundColor)")
    }
}
