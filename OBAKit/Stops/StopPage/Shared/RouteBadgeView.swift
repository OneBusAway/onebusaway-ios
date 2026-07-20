//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Rounded-square route identity badge — the only place route color appears in
/// the departure list rows; the trip panel separately uses it for the vehicle
/// glyph and approach timeline. Spec §4.3 still holds: route color never tints
/// countdowns or adherence text.
///
/// Text color is WCAG-aware: the agency's `route_text_color` is honored when
/// it clears the contrast threshold, else black/white is computed. Under
/// system Increase Contrast the gradient flattens and the threshold rises to
/// 7:1 (see docs/superpowers/specs/2026-07-20-stop-ui-accessibility-design.md).
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var routeTextColor: Color?
    var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorSchemeContrast) private var contrast

    private var resolvedTextColor: Color {
        let minimumRatio: CGFloat = contrast == .increased ? 7.0 : 4.5
        let background = UIColor(routeColor)
        let preferred = routeTextColor.map { UIColor($0) }
        return Color(uiColor: background.badgeTextColor(preferring: preferred, minimumRatio: minimumRatio))
    }

    /// The gradient's luminance ramp is a small, intentional deviation from
    /// the flat color the ratio is computed against; Increase Contrast goes
    /// flat so the strict 7:1 tier has no ambiguity.
    private var backgroundStyle: AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(routeColor) : AnyShapeStyle(routeColor.gradient)
    }

    var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}
