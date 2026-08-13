//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
@testable import OBAKitCore

struct RouteBadgeStyleTests {

    /// #767676 is the canonical WCAG AA boundary gray: white text over it is
    /// ~4.54:1 — above the standard 4.5 tier, below the increased 7.0 tier.
    /// One color, two contrast settings, two different outcomes proves the
    /// tier wiring (the WCAG tests all pass minimumRatio explicitly and
    /// cannot catch a mis-wired threshold).
    @Test @MainActor func increasedContrastRaisesTheThreshold() {
        let gray = Color(red: 118.0/255.0, green: 118.0/255.0, blue: 118.0/255.0)

        // UIColor(Color) round-trips through a different color space than a
        // directly-constructed UIColor.white/.black, so `==` isn't reliable
        // here; compare the channel average instead.
        func averageChannel(_ color: Color) -> CGFloat {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return (red + green + blue) / 3
        }

        #expect(averageChannel(RouteBadgeStyle.textColor(routeColor: gray, routeTextColor: .white, contrast: .standard)) > 0.99)
        #expect(averageChannel(RouteBadgeStyle.textColor(routeColor: gray, routeTextColor: .white, contrast: .increased)) < 0.01)
    }
}
