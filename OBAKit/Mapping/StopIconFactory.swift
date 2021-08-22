//
//  StopIconFactory.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Renders a stop icon. This is the transport type icon, a directional arrow, and all of the other adornments that go with it.
class StopIconFactory: NSObject {
    private let kUseDebugColors = false

    private let iconSize: CGFloat

    private let iconCache = NSCache<NSString, UIImage>()

    /// Initializes a `StopIconFactory`.
    /// - Parameter iconSize: The width and height of the icons that will be generated.
    /// - Parameter themeColors: A ThemeColors object.
    public init(iconSize: CGFloat, themeColors: ThemeColors) {
        self.iconSize = iconSize
        self.themeColors = themeColors
    }

    /// Creates a stop icon image.
    /// - Parameter stop: The `Stop` for which an image will be rendered.
    /// - Parameter isBookmarked: Whether the stop has been bookmarked, which will result in it receiving a different visual treatment.
    /// - Returns: An image representing `stop`.
    public func buildIcon(for stop: Stop, isBookmarked: Bool, traits: UITraitCollection) -> UIImage {
        let isDarkMode = traits.userInterfaceStyle == .dark

        // First, let's compose the cache key out of the name and orientation, then
        // see if we've already got one that matches.
        let key = cacheKey(for: stop, isBookmarked: isBookmarked, isDarkMode: isDarkMode) as NSString

        // If an image already exists, then go ahead and return it.
        if let cachedImage = iconCache.object(forKey: key) {
            return cachedImage
        }

        // Otherwise, generate a new stop icon and add it to the cache.
        let image = renderImage(for: stop, isBookmarked: isBookmarked)
        iconCache.setObject(image, forKey: key)

        return image
    }

    // MARK: - Colors

    private let themeColors: ThemeColors

    private var chevronFillColor: UIColor {
        themeColors.stopArrowFillColor
    }

    private var fillColor: UIColor {
        themeColors.stopAnnotationFillColor
    }

    private var transportIconColor: UIColor {
        themeColors.label
    }

    /// Stroke color for the badge and its directional arrow.
    private var strokeColor: UIColor {
        themeColors.stopAnnotationStrokeColor
    }

    private var bookmarkedStrokeColor: UIColor {
        themeColors.brand
    }

    // MARK: - Sizes

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
    /// - Parameter isBookmarked: Whether `stop` has been bookmarked by the user.
    /// - Returns: An image representing `stop`.
    private func renderImage(for stop: Stop, isBookmarked: Bool) -> UIImage {
        return renderIcon(routeType: stop.prioritizedRouteTypeForDisplay, direction: stop.direction, isBookmarked: isBookmarked)
    }

    /// Draws a stop icon image with the specified properties.
    func renderIcon(routeType: Route.RouteType, direction: Direction, isBookmarked: Bool) -> UIImage {
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

            if isBookmarked {
                self.drawBackground(color: bookmarkedStrokeColor, rect: rect, context: ctx)
                self.drawIcon(routeType: routeType, rect: rect, context: ctx, color: .white)
            }
            else {
                self.drawBackground(color: fillColor, rect: rect, context: ctx)
                self.drawIcon(routeType: routeType, rect: rect, context: ctx)
            }

            self.drawBorder(color: strokeColor, rect: rect, context: ctx)

            self.drawArrowImage(direction: direction, strokeColor: strokeColor, rect: imageBounds, context: ctx)
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
    /// - Parameter color: An override color for filling the icon. Pass `nil` to use the default color.
    private func drawIcon(routeType: Route.RouteType, rect: CGRect, context: CGContext, color: UIColor? = nil) {
        context.pushPop {
            let image = Icons.transportIcon(from: routeType).tinted(color: color ?? transportIconColor)
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
    /// - Parameter isBookmarked: If `stop` has been bookmarked by the user.
    /// - Returns: A cache key that will uniquely represent this stop with its desired visual treatment.
    private func cacheKey(for stop: Stop, isBookmarked: Bool, isDarkMode: Bool) -> String {
        let routeType = stop.prioritizedRouteTypeForDisplay.rawValue
        let stopID = isBookmarked ? stop.id : "AnyStop"
        let appearanceStyle = isDarkMode ? "dark" : "light"
        let direction = stop.direction.rawValue
        let cacheKey = "\(stopID):\(routeType):\(direction)(\(iconSize)x\(iconSize)):\(appearanceStyle)"

        return cacheKey
    }
}
