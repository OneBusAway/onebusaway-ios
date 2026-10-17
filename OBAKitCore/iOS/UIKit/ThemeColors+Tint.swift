//
//  ThemeColors+Tint.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import os
import UIKit

public extension ThemeColors {
    /// The brand colour as a tint for text and controls: bar buttons, links,
    /// switches, the selected tab. `brand` itself is 2.76:1 on white in the
    /// OneBusAway app, short of the 3:1 controls need, let alone the 4.5:1 for
    /// text. This is `brand` darkened (or, in dark mode, lightened) just enough
    /// to reach 4.5:1 on the system backgrounds, so each app keeps its own hue.
    /// Keep `brand` for fills and large glyphs.
    ///
    /// Not main-actor isolated: list rows and headers build their accessories
    /// from `nonisolated` configurations.
    var brandTint: UIColor {
        // Built once per `ThemeColors`, not on every read: rows, buttons and
        // SwiftUI views read this each time they're configured.
        if let cached = objc_getAssociatedObject(self, &brandTintKey) as? UIColor {
            return cached
        }
        // Worked out the first time each appearance is drawn, then kept: UIKit
        // resolves the tint of every tinted view, often, and the contrast search
        // is a loop. Resolving with the traits UIKit hands in also avoids building
        // trait collections here, which is main-actor work.
        let variants = OSAllocatedUnfairLock<[Appearance: UIColor]>(initialState: [:])
        let tint = UIColor { [brand] traits in
            let key = Appearance(style: traits.userInterfaceStyle == .dark ? .dark : .light, contrast: traits.accessibilityContrast == .high ? .high : .normal)
            if let known = variants.withLock({ $0[key] }) { return known }
            // The lighter of the two grouped backgrounds is the harder one in dark
            // mode, and the darker one in light mode.
            let background: UIColor = key.style == .dark ? .secondarySystemGroupedBackground : .systemGroupedBackground
            let color = brand.resolvedColor(with: traits).adjusted(toContrast: 4.5, against: background.resolvedColor(with: traits))
            variants.withLock { $0[key] = color }
            return color
        }
        objc_setAssociatedObject(self, &brandTintKey, tint, .OBJC_ASSOCIATION_RETAIN)
        return tint
    }
}

/// The associated-object key for `brandTint`'s cache. Only its address is used,
/// and the association itself is atomic.
nonisolated(unsafe) private var brandTintKey: UInt8 = 0

private struct Appearance: Hashable {
    let style: UIUserInterfaceStyle
    let contrast: UIAccessibilityContrast
}

#endif // os(iOS)
