//
//  ImageBadgeRenderer.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreGraphics
import UIKit

/// Creates image 'badges', or squircles with overlayed monochromatic images.
public class ImageBadgeRenderer: NSObject {

    private let fillColor: UIColor
    private let backgroundColor: UIColor
    public let badgeSize: CGFloat

    /// Creates an `ImageBadgeRenderer` with a default `badgeSize` of 128.0.
    /// - Parameters:
    ///   - fillColor: The fill color of the icon.
    ///   - backgroundColor: The background color of the badge.
    ///   - badgeSize: The size of the badge in points.
    public init(fillColor: UIColor, backgroundColor: UIColor, badgeSize: CGFloat = 128.0) {
        self.fillColor = fillColor
        self.backgroundColor = backgroundColor
        self.badgeSize = badgeSize
    }

    public func drawImageOnRoundedRect(_ image: UIImage) -> UIImage {
        let frame = CGRect(origin: .zero, size: CGSize(width: badgeSize, height: badgeSize))
        let renderer = UIGraphicsImageRenderer(bounds: frame)

        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext

            let bezierPath = UIBezierPath(roundedRect: frame, cornerRadius: self.cornerRadius)
            ctx.setFillColor(self.backgroundColor.cgColor)
            bezierPath.fill(with: .normal, alpha: 1.0)

            ctx.setFillColor(self.fillColor.cgColor)
            image.withRenderingMode(.alwaysTemplate).draw(in: calculateFrame(for: image))
        }
    }

    private var iconSize: CGFloat {
        badgeSize * 0.75
    }

    private var iconInset: CGFloat {
        badgeSize * 0.125
    }

    private var cornerRadius: CGFloat {
        iconInset * 2.0
    }

    private func aspectFit(aspect: CGSize, boundingSize: CGSize) -> CGSize {
        var boundingSize = boundingSize
        let mW = boundingSize.width / aspect.width
        let mH = boundingSize.height / aspect.height
        if mW > mH {
            boundingSize.width = boundingSize.height / aspect.height * aspect.width
        }
        else if mH > mW {
            boundingSize.height = boundingSize.width / aspect.width * aspect.height
        }
        return boundingSize
    }

    private func calculateFrame(for image: UIImage) -> CGRect {
        let scaledImageSize = aspectFit(aspect: image.size, boundingSize: CGSize(width: iconSize, height: iconSize))

        let x = (badgeSize - scaledImageSize.width) / 2.0
        let y = (badgeSize - scaledImageSize.height) / 2.0
        return CGRect(x: x, y: y, width: scaledImageSize.width, height: scaledImageSize.height)
    }
}
