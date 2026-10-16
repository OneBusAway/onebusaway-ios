//
//  HostedRender.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import UIKit

/// Renders a SwiftUI view through a real `UIHostingController` in a scene-attached
/// window, in light mode, and returns its pixels.
///
/// `ImageRenderer` is not a substitute: it draws `List` and other UIKit-backed
/// containers as a placeholder, and some bugs only appear inside a `List` row.
@MainActor
struct HostedRender {
    let width: Int
    let height: Int
    /// RGBA8, row-major from the top-left.
    private let bytes: [UInt8]

    init<V: View>(_ view: V, size: CGSize) throws {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(windowScene: try testWindowScene())
        window.overrideUserInterfaceStyle = .light
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        // One run-loop pass so List cells finish their first layout.
        RunLoop.main.run(until: Date())

        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        let uiImage = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(uiImage.cgImage)

        // Redraw into a known RGBA8 layout so pixel reads don't depend on the
        // renderer's choice of byte order.
        let width = cgImage.width, height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        self.width = width
        self.height = height
        self.bytes = buffer
    }

    /// Unweighted mean of a pixel's RGB channels, 0...255 — a brightness, not WCAG
    /// relative luminance. `(0, 0)` is the top-left.
    func luminance(x: Int, y: Int) -> Int {
        let i = (y * width + x) * 4
        return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
    }

    /// The bounding box, in pixels, of every pixel within 6/255 of `color` on each
    /// channel. `nil` if none match.
    func boundingBox(of color: UIColor) throws -> CGRect? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // A color with no RGB form would leave the target black and match the background.
        try #require(color.getRed(&r, green: &g, blue: &b, alpha: &a), "\(color) has no RGB components")
        let target = [r, g, b].map { Int(($0 * 255).rounded()) }
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        forEachPixel(in: CGRect(x: 0, y: 0, width: width, height: height)) { x, y, red, green, blue in
            guard abs(red - target[0]) <= 6, abs(green - target[1]) <= 6, abs(blue - target[2]) <= 6 else { return }
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// How many pixels in `region` are near-white (every channel at least 200/255).
    func lightPixelCount(in region: CGRect) -> Int {
        var count = 0
        forEachPixel(in: region) { _, _, red, green, blue in
            if red >= 200 && green >= 200 && blue >= 200 { count += 1 }
        }
        return count
    }

    /// Visits each pixel of `region`, clipped to the image, with its coordinates and RGB.
    private func forEachPixel(in region: CGRect, _ body: (_ x: Int, _ y: Int, _ red: Int, _ green: Int, _ blue: Int) -> Void) {
        let clipped = region.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull else { return }
        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            for x in Int(clipped.minX)..<Int(clipped.maxX) {
                let i = (y * width + x) * 4
                body(x, y, Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
            }
        }
    }
}
