//
//  StopIconFactory.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/8/19.
//

import UIKit

/// Renders a stop icon 'badge'. In other words, the core of a stop annotation view's rendered appearance on the map.
public class StopIconFactory: NSObject {
    private let kUseDebugColors = false

    private let iconSize: CGFloat

    private var iconBackgroundColor: UIColor = .white // abxoxo dark mode
    private var chevronFillColor: UIColor = .red // abxoxo dark mode
    private var textColor: UIColor = .white
    private let iconCache = NSCache<NSString, UIImage>()

    public init(iconSize: CGFloat) {
        self.iconSize = iconSize
    }

    public func buildIcon(for stop: Stop, strokeColor: UIColor, fillColor: UIColor) -> UIImage {
        // First, let's compose the cache key out of the name and orientation, then
        // see if we've already got one that matches.

        let key = cacheKey(for: stop, strokeColor: strokeColor, fillColor: fillColor) as NSString

        if let cachedImage = iconCache.object(forKey: key) {
            return cachedImage
        }

        let image = renderImage(for: stop, strokeColor: strokeColor, fillColor: fillColor)
        iconCache.setObject(image, forKey: key)

        return image
    }

    private let arrowTrackSize: CGFloat = 8.0
    private let arrowSize = CGSize(width: 12, height: 6)
    private let arrowStroke: CGFloat = 1.0
    private let cornerRadius: CGFloat = 4.0
    private let borderWidth: CGFloat = 2.0
    private let backgroundAlpha: CGFloat = 0.9
    private let iconInset: CGFloat = 6.0

    // MARK: - Rendering Steps

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
            self.drawBorder(rect: rect, color: strokeColor, context: ctx)
            self.drawIcon(routeType: stop.prioritizedRouteTypeForDisplay, rect: rect, context: ctx)
            self.drawArrowImage(direction: stop.direction, strokeColor: strokeColor, rect: imageBounds, context: ctx)
        }
    }

    private func drawBackground(color: UIColor, rect: CGRect, context: CGContext) {
        context.pushPop {
            // we inset the rect the 1/2 px in order ensure that it doesn't 'bleed' past
            // the edge of the rounded rect border that we'll draw in drawBorder()
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius)
            context.setFillColor(color.cgColor)
            bezierPath.fill(with: .normal, alpha: backgroundAlpha)
        }
    }

    private func drawBorder(rect: CGRect, color: UIColor, context: CGContext) {
        context.pushPop {
            let inset = borderWidth / 2.0
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: cornerRadius)
            bezierPath.lineWidth = borderWidth
            context.setStrokeColor(color.cgColor)
            bezierPath.stroke()
        }
    }

    private func drawIcon(routeType: RouteType, rect: CGRect, context: CGContext) {
        context.pushPop {
            let image = Icons.transportIcon(from: routeType)
            image.draw(in: rect.insetBy(dx: iconInset, dy: iconInset))
        }
    }

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

    private func cacheKey(for stop: Stop, strokeColor: UIColor, fillColor: UIColor) -> String {
        let routeType = stop.prioritizedRouteTypeForDisplay.rawValue
        let direction = stop.direction.rawValue
        let hexStroke = strokeColor.toHex ?? ""
        let hexFill = fillColor.toHex ?? ""
        let cacheKey = "\(routeType):\(direction)(\(iconSize)x\(iconSize))-\(hexStroke)-\(hexFill)"

        return cacheKey
    }
}
