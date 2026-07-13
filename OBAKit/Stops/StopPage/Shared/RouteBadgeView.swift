//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge — the only place route color appears in
/// the departure list rows; the trip panel separately uses it for the vehicle
/// glyph and approach timeline. Spec §4.3 still holds: route color never tints
/// countdowns or adherence text.
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(routeColor.gradient, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}
