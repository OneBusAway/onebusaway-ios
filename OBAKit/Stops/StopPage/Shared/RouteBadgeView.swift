//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge. The ONLY place (besides the grouped
/// card stripe) that renders the route's brand color (§4.3).
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var size: CGFloat = 44

    var body: some View {
        Text(routeShortName)
            .font(.system(size: routeShortName.count <= 2 ? 18 : 13, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(routeColor, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}
