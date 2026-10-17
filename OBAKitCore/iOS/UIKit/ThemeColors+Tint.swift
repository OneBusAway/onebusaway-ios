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
    var brandTint: UIColor {
        UIColor { [brand] traits in
            // The lighter of the two grouped backgrounds is the harder one in dark
            // mode, and the darker one in light mode.
            let background: UIColor = traits.userInterfaceStyle == .dark ? .secondarySystemGroupedBackground : .systemGroupedBackground
            return brand.resolvedColor(with: traits)
                .adjusted(toContrast: 4.5, against: background.resolvedColor(with: traits))
        }
    }
}

#endif // os(iOS)
