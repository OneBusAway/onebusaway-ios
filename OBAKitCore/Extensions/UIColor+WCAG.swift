//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// WCAG 2.1 contrast math (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).
// Distinct from `isLightColor`/`contrastingTextColor` in UIKitExtensions.swift,
// which use a perceived-luminance heuristic unsuitable for contrast-ratio checks.
public extension UIColor {

    /// WCAG 2.1 relative luminance: 0 (black) … 1 (white), with piecewise
    /// sRGB linearization.
    ///
    /// Assumes an RGB-convertible color (pattern colors degrade to luminance
    /// 0); alpha is ignored — colors are treated as opaque.
    var wcagRelativeLuminance: CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linearize(_ channel: CGFloat) -> CGFloat {
            let clamped = min(max(channel, 0), 1)
            return clamped <= 0.03928 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    /// WCAG 2.1 contrast ratio between the receiver and `other`:
    /// 1 (identical) … 21 (black/white). Symmetric.
    func wcagContrastRatio(against other: UIColor) -> CGFloat {
        let lighter = max(wcagRelativeLuminance, other.wcagRelativeLuminance)
        let darker = min(wcagRelativeLuminance, other.wcagRelativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Text color for content drawn over the receiver. Honors `preferred`
    /// (e.g. the agency's GTFS `route_text_color`) when it clears
    /// `minimumRatio`; otherwise returns black or white, whichever contrasts
    /// more. Guarantees the best achievable contrast when no candidate
    /// clears the bar.
    func badgeTextColor(preferring preferred: UIColor?, minimumRatio: CGFloat) -> UIColor {
        if let preferred, preferred.wcagContrastRatio(against: self) >= minimumRatio {
            return preferred
        }

        let blackRatio = UIColor.black.wcagContrastRatio(against: self)
        let whiteRatio = UIColor.white.wcagContrastRatio(against: self)
        return blackRatio >= whiteRatio ? .black : .white
    }
}
