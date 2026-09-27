//
//  OnDemandServiceColors.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// Spec 2.3: one resolved colour per service, shared by the polygon, pin,
/// card icon and bar; collisions take the fallback palette by service id order.
enum OnDemandServiceColors {

    static let fallbackPalette: [UIColor] = [
        UIColor(red: 0x3b / 255.0, green: 0x82 / 255.0, blue: 0xf6 / 255.0, alpha: 1),
        UIColor(red: 0xd9 / 255.0, green: 0x77 / 255.0, blue: 0x06 / 255.0, alpha: 1),
        UIColor(red: 0x7c / 255.0, green: 0x3a / 255.0, blue: 0xed / 255.0, alpha: 1),
        UIColor(red: 0xdb / 255.0, green: 0x27 / 255.0, blue: 0x77 / 255.0, alpha: 1),
        UIColor(red: 0x08 / 255.0, green: 0x91 / 255.0, blue: 0xb2 / 255.0, alpha: 1),
        UIColor(red: 0x65 / 255.0, green: 0xa3 / 255.0, blue: 0x0d / 255.0, alpha: 1)
    ]

    /// WCAG minimum for normal text over the bar colour.
    private static let minimumContrastRatio: CGFloat = 4.5

    static func baseColor(for service: OnDemandService, brand: UIColor = ThemeColors.shared.brand) -> UIColor {
        service.route?.color ?? brand
    }

    /// `match`'s collision-resolved colour from `colors`, else its base colour.
    static func color(for match: OnDemandServiceMatch, in colors: [String: UIColor]) -> UIColor {
        colors[match.id] ?? baseColor(for: match.service)
    }

    static func resolvedColors(for services: [OnDemandService], brand: UIColor = ThemeColors.shared.brand) -> [String: UIColor] {
        var used = Set<String>()
        var result: [String: UIColor] = [:]
        var nextFallback = 0

        for service in services.sorted(by: { $0.id < $1.id }) {
            var color = baseColor(for: service, brand: brand)
            if used.contains(color.rgbKey) {
                while nextFallback < fallbackPalette.count, used.contains(fallbackPalette[nextFallback].rgbKey) {
                    nextFallback += 1
                }
                if nextFallback < fallbackPalette.count {
                    color = fallbackPalette[nextFallback]
                    nextFallback += 1
                }
            }
            used.insert(color.rgbKey)
            result[service.id] = color
        }
        return result
    }

    /// The route's `textColor` when it has one; otherwise black or white,
    /// whichever clears 4.5:1 against `background`.
    static func textColor(for service: OnDemandService, on background: UIColor) -> UIColor {
        if let textColor = service.route?.textColor {
            return textColor
        }
        return background.badgeTextColor(preferring: nil, minimumRatio: minimumContrastRatio)
    }
}

private extension UIColor {
    var rgbKey: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
