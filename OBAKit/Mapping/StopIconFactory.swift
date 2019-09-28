//
//  StopIconFactory.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/8/19.
//

import UIKit
import OBAKitCore

/// Renders a stop icon. This is the transport type icon, a directional arrow, and all of the other adornments that go with it.
public class StopIconFactory: NSObject {
    private let kUseDebugColors = false

    private let iconSize: CGFloat

    private var chevronFillColor: UIColor = .red // abxoxo dark mode
    private let iconCache = NSCache<NSString, UIImage>()

    /// Initializes a `StopIconFactory`.
    /// - Parameter iconSize: The width and height of the icons that will be generated.
    public init(iconSize: CGFloat) {
        self.iconSize = iconSize
    }

    /// Creates a stop icon image.
    /// - Parameter stop: The `Stop` for which an image will be rendered.
    /// - Parameter strokeColor: The border color of the icon.
    /// - Parameter fillColor: The interior color of the icon.
    public func buildIcon(for stop: Stop, strokeColor: UIColor, fillColor: UIColor) -> UIImage {
        // First, let's compose the cache key out of the name and orientation, then
        // see if we've already got one that matches.
        let key = cacheKey(for: stop, strokeColor: strokeColor, fillColor: fillColor) as NSString

        // If an image already exists, then go ahead and return it.
        if let cachedImage = iconCache.object(forKey: key) {
            return cachedImage
        }

        // Otherwise, generate a new stop icon and add it to the cache.
        let image = renderImage(for: stop, strokeColor: strokeColor, fillColor: fillColor)
        iconCache.setObject(image, forKey: key)

        return image
    }

    /// The outer gutter for the directional arrow.
    private let arrowTrackSize: CGFloat = 8.0

    /// The size of the directional arrow.
    private let arrowSize = CGSize(width: 12, height: 6)

    /// The line width of the arrow's border.
    private let arrowStroke: CGFloat = 1.0

    /// The corner radius of the icon.
    private let cornerRadius: CGFloat = 4.0

    /// The stroke width.
    private let borderWidth: CGFloat = 2.0

    /// The opacity of the icon's background.
    private let backgroundAlpha: CGFloat = 0.9

    /// The drawing inset of the transport glyph.
    private let transportGlyphInset: CGFloat = 6.0

    // MARK: - Rendering Steps

    /// Draws the stop icon image.
    /// - Parameter stop: The `Stop` for which an icon will be generated.
    /// - Parameter strokeColor: The border color.
    /// - Parameter fillColor: The interior color.
    private func renderImage(for stop: Stop, strokeColor: UIColor, fillColor: UIColor) -> UIImage {
        let imageBounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let rect = imageBounds.insetBy(dx: arrowTrackSize, dy: arrowTrackSize)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: iconSize, height: iconSize))
        return renderer.image { [weak self] rendererContext in
            guard let self = self else { return }
            let ctx = rendererContext.cgContext

            if kUseDebugColors {
                UIColor.magenta.setFill()
                UIRectFill(imageBounds)
            }

            self.drawBackground(color: fillColor, rect: rect, context: ctx)
            self.drawBorder(color: strokeColor, rect: rect, context: ctx)
            self.drawIcon(routeType: stop.prioritizedRouteTypeForDisplay, rect: rect, context: ctx)
            self.drawArrowImage(direction: stop.direction, strokeColor: strokeColor, rect: imageBounds, context: ctx)
        }
    }

    /// Draws the background color of the icon, accounting for the corner radius.
    /// - Parameter color: Background color.
    /// - Parameter rect: The rectangle in which to draw.
    /// - Parameter context: The Core Graphics context in which drawing happens.
    private func drawBackground(color: UIColor, rect: CGRect, context: CGContext) {
        context.pushPop {
            // we inset the rect the 1/2 px in order ensure that it doesn't 'bleed' past
            // the edge of the rounded rect border that we'll draw in drawBorder()
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius)
            context.setFillColor(color.cgColor)
            bezierPath.fill(with: .normal, alpha: backgroundAlpha)
        }
    }

    /// Strokes the border color onto the icon.
    /// - Parameter color: Stroke/border color.
    /// - Parameter rect: The rectangle in which to draw.
    /// - Parameter context: The Core Graphics context in which drawing happens.
    private func drawBorder(color: UIColor, rect: CGRect, context: CGContext) {
        context.pushPop {
            let inset = borderWidth / 2.0
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: cornerRadius)
            bezierPath.lineWidth = borderWidth
            context.setStrokeColor(color.cgColor)
            bezierPath.stroke()
        }
    }

    /// Draws the transport glyph onto the icon.
    /// - Note: Drawing is inset from `rect` by `transportGlyphInset` points.
    ///
    /// - Parameter routeType: The transport glyph type that will be drawn.
    /// - Parameter rect: The rectangle in which to draw.
    /// - Parameter context: The Core Graphics context in which drawing happens.
    private func drawIcon(routeType: RouteType, rect: CGRect, context: CGContext) {
        context.pushPop {
            let image = Icons.transportIcon(from: routeType)
            image.draw(in: rect.insetBy(dx: transportGlyphInset, dy: transportGlyphInset))
        }
    }

    /// Draws the directional arrow in the outer track of the image.
    /// - Parameter direction: The direction in which to draw the arrow.
    /// - Parameter strokeColor: The border color of the arrow.
    /// - Parameter rect: The rectangle in which to draw.
    /// - Parameter context: The Core Graphics context in which drawing happens.
    private func drawArrowImage(direction: Direction, strokeColor: UIColor, rect: CGRect, context: CGContext) { // swiftlint:disable:this function_body_length
        guard direction != .unknown else { return }

        context.pushPop {
            let halfWidth = arrowSize.width / 2.0
            let rightLeg = arrowSize.width / sqrt(2.0)
            let cornerTranslation: CGFloat = 3.0

            let triangle = UIBezierPath()
            triangle.lineWidth = arrowStroke

            chevronFillColor.setFill()
            strokeColor.setStroke()

            switch direction {
            case .n:
                triangle.move(to: CGPoint(x: rect.midX, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.midX + halfWidth, y: rect.minY + arrowSize.height))
                triangle.addLine(to: CGPoint(x: rect.midX - halfWidth, y: rect.minY + arrowSize.height))
                triangle.addLine(to: CGPoint(x: rect.midX, y: rect.minY))

            case .ne:
                triangle.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rightLeg))
                triangle.addLine(to: CGPoint(x: rect.maxX - rightLeg, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                triangle.apply(CGAffineTransform(translationX: -cornerTranslation, y: cornerTranslation))

            case .nw:
                triangle.move(to: CGPoint(x: rect.minX, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rightLeg))
                triangle.addLine(to: CGPoint(x: rect.minX + rightLeg, y: rect.minY))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                triangle.apply(CGAffineTransform(translationX: cornerTranslation, y: cornerTranslation))

            case .e:
                triangle.move(to: CGPoint(x: rect.maxX, y: rect.midY))
                triangle.addLine(to: CGPoint(x: rect.maxX - arrowSize.height, y: rect.midY + halfWidth))
                triangle.addLine(to: CGPoint(x: rect.maxX - arrowSize.height, y: rect.midY - halfWidth))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))

            case .w:
                triangle.move(to: CGPoint(x: rect.minX, y: rect.midY))
                triangle.addLine(to: CGPoint(x: rect.minX + arrowSize.height, y: rect.midY + halfWidth))
                triangle.addLine(to: CGPoint(x: rect.minX + arrowSize.height, y: rect.midY - halfWidth))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.midY))

            case .s:
                triangle.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.midX + halfWidth, y: rect.maxX - arrowSize.height))
                triangle.addLine(to: CGPoint(x: rect.midX - halfWidth, y: rect.maxX - arrowSize.height))
                triangle.addLine(to: CGPoint(x: rect.midX, y: rect.maxX))

            case .sw:
                triangle.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rightLeg))
                triangle.addLine(to: CGPoint(x: rect.minX + rightLeg, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                triangle.apply(CGAffineTransform(translationX: cornerTranslation, y: -cornerTranslation))

            case .se:
                triangle.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightLeg))
                triangle.addLine(to: CGPoint(x: rect.maxX - rightLeg, y: rect.maxY))
                triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                triangle.apply(CGAffineTransform(translationX: -cornerTranslation, y: -cornerTranslation))

            case .unknown:
                break
            }

            triangle.close()
            triangle.fill()
            triangle.stroke()
        }
    }

    // MARK: - Private Helpers

    /// Calculates a cache key for stop icons.
    /// - Parameter stop: The `Stop`.
    /// - Parameter strokeColor: The border color.
    /// - Parameter fillColor: The fill color.
    private func cacheKey(for stop: Stop, strokeColor: UIColor, fillColor: UIColor) -> String {
        let routeType = stop.prioritizedRouteTypeForDisplay.rawValue
        let direction = stop.direction.rawValue
        let hexStroke = strokeColor.toHex ?? ""
        let hexFill = fillColor.toHex ?? ""
        let cacheKey = "\(routeType):\(direction)(\(iconSize)x\(iconSize))-\(hexStroke)-\(hexFill)"

        return cacheKey
    }
}
