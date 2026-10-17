//
//  ThemeColors+Tint.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import UIKit

public extension ThemeColors {
    /// The brand colour as a tint for text and controls: bar buttons, links,
    /// switches, the selected tab. `brand` itself is 2.76:1 on white in the
    /// OneBusAway app, short of the 3:1 controls need, let alone the 4.5:1 for
    /// text. This is `brand` darkened (or, in dark mode, lightened) just enough
    /// to reach 4.5:1 on the system backgrounds, so each app keeps its own hue.
    /// Keep `brand` for fills and large glyphs.
    @MainActor
    var brandTint: UIColor {
        // Worked out once for each appearance the tint can be drawn in, rather than
        // on every resolve: UIKit resolves the tint of every tinted view, often.
        var variants: [Appearance: UIColor] = [:]
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = contrast }
                // The lighter of the two grouped backgrounds is the harder one in
                // dark mode, and the darker one in light mode.
                let background: UIColor = style == .dark ? .secondarySystemGroupedBackground : .systemGroupedBackground
                variants[Appearance(style: style, contrast: contrast)] = brand.resolvedColor(with: traits)
                    .adjusted(toContrast: 4.5, against: background.resolvedColor(with: traits))
            }
        }
        return UIColor { [variants, brand] traits in
            let key = Appearance(style: traits.userInterfaceStyle == .dark ? .dark : .light, contrast: traits.accessibilityContrast == .high ? .high : .normal)
            return variants[key] ?? brand
        }
    }
}

private struct Appearance: Hashable {
    let style: UIUserInterfaceStyle
    let contrast: UIAccessibilityContrast
}

#endif // os(iOS)
