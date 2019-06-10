//
//  StopIconFactory.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/8/19.
//

import UIKit

/// Renders a stop icon 'badge'. In other words, the core of a stop annotation view's rendered appearance on the map.
@objc(OBAStopIconFactory) public class StopIconFactory: NSObject {
    private let iconSize: CGFloat

    private var iconBackgroundColor: UIColor = .white
    private var chevronFillColor: UIColor = .red
    private var textColor: UIColor = .white
    private let iconCache = NSCache<NSString, UIImage>()

    @objc public init(iconSize: CGFloat) {
        self.iconSize = iconSize
    }

    @objc public func buildIcon(for stop: Stop, strokeColor: UIColor) -> UIImage {
        // First, let's compose the cache key out of the name and orientation, then
        // see if we've already got one that matches.

        let key = cacheKey(for: stop, strokeColor: strokeColor) as NSString

        if let cachedImage = iconCache.object(forKey: key) {
            return cachedImage
        }

        let image = renderImage(for: stop, strokeColor: strokeColor)
        iconCache.setObject(image, forKey: key)

        return image
    }

    private let arrowTrackSize: CGFloat = 8.0
    private let arrowSize = CGSize(width: 12, height: 6)
    private let cornerRadius: CGFloat = 4.0
    private let borderWidth: CGFloat = 2.0
    private let borderColor = UIColor.black
    private let backgroundColor = UIColor.white
    private let backgroundAlpha: CGFloat = 0.9
    private let iconInset: CGFloat = 8.0

    // MARK: - Rendering Steps

    private func renderImage(for stop: Stop, strokeColor: UIColor) -> UIImage {
        let imageBounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let rect = imageBounds.insetBy(dx: arrowTrackSize, dy: arrowTrackSize)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: iconSize, height: iconSize))
        return renderer.image { [weak self] rendererContext in
            guard let self = self else { return }
            let ctx = rendererContext.cgContext

            self.drawBackground(rect: rect, context: ctx)
            self.drawBorder(rect: rect, context: ctx)
            self.drawIcon(routeType: stop.prioritizedRouteTypeForDisplay, rect: rect, context: ctx)
            self.drawArrowImage(direction: stop.direction, rect: imageBounds, context: ctx)
        }
    }

    private func drawBackground(rect: CGRect, context: CGContext) {
        context.pushPop {
            // we inset the rect the 1/2 px in order ensure that it doesn't 'bleed' past
            // the edge of the rounded rect border that we'll draw in drawBorder()
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius)
            context.setFillColor(backgroundColor.cgColor)
            bezierPath.fill(with: .normal, alpha: backgroundAlpha)
        }
    }

    private func drawBorder(rect: CGRect, context: CGContext) {
        context.pushPop {
            let inset = borderWidth / 2.0
            let bezierPath = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: cornerRadius)
            bezierPath.lineWidth = borderWidth
            context.setStrokeColor(borderColor.cgColor)
            bezierPath.stroke()
        }
    }

    private func drawIcon(routeType: RouteType, rect: CGRect, context: CGContext) {
        context.pushPop {
            let image = Icons.transportIcon(from: routeType)
            image.draw(in: rect.insetBy(dx: iconInset, dy: iconInset))
        }
    }

    private func drawArrowImage(direction: Direction, rect: CGRect, context: CGContext) {
        guard direction != .unknown else { return }

        context.pushPop {
            let image = renderArrowImage(direction: direction)
            let point = drawLocation(direction: direction, rect: rect, imageSize: image.size)
            image.draw(at: point)
        }
    }

    // MARK: - Private Helpers

    private func drawLocation(direction: Direction, rect: CGRect, imageSize: CGSize) -> CGPoint {
        let halfImageWidth = imageSize.width / 2.0
        let halfHeight = imageSize.height / 2.0

        switch direction {
        case .nw: return CGPoint(x: rect.minX, y: rect.minY)
        case .n:  return CGPoint(x: rect.midX - halfImageWidth, y: rect.minY)
        case .ne: return CGPoint(x: rect.maxX - imageSize.width, y: rect.minY)
        case .w:  return CGPoint(x: rect.minX, y: rect.midY - halfHeight)
        case .e:  return CGPoint(x: rect.maxX - imageSize.width, y: rect.midY - halfHeight)
        case .sw: return CGPoint(x: rect.minX, y: rect.maxY - imageSize.height)
        case .s:  return CGPoint(x: rect.midX - halfImageWidth, y: rect.maxY - imageSize.height)
        default:  return CGPoint.zero
        }
    }

    private func renderArrowImage(direction: Direction) -> UIImage {
        return UIImage(named: "bluedot", in: Bundle(for: type(of: self)), compatibleWith: nil)!
    }

    private func rotationAngleForDirection(_ direction: Direction) -> CGFloat {
        switch direction {
        case .n: return .pi
        case .ne: return 1.25 * .pi
        case .e: return 1.5 * .pi
        case .se: return 1.75 * .pi
        case .s: return 2.0 * .pi
        case .sw: return 0.25 * .pi
        case .w: return 0.5 * .pi
        case .nw: return 0.75 * .pi
        default:
            fatalError()
        }
    }

    private func cacheKey(for stop: Stop, strokeColor: UIColor) -> String {
        let routeType = stop.prioritizedRouteTypeForDisplay.rawValue
        let direction = stop.direction.rawValue
        let hexColor = strokeColor.toHex ?? ""
        let cacheKey = "\(routeType):\(direction)(\(iconSize)x\(iconSize))-\(hexColor)"

        return cacheKey
    }
}
