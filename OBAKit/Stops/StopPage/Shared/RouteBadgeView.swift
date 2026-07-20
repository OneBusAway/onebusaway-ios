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
    /// When true (Settings > Accessibility > "Reduce colors on stop page"),
    /// route color shrinks to a thin vertical bar and the route number uses
    /// the standard label color — same information, minimal color area.
    var reducedColors: Bool = false

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 5
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

    private var badgeFont: Font {
        .system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy)
    }

    var body: some View {
        Group {
            if reducedColors {
                reducedBody
            } else {
                standardBody
            }
        }
        .frame(width: size * scale, height: size * scale)
        .accessibilityHidden(true) // route name is in the row's combined label
    }

    private var standardBody: some View {
        Text(routeShortName)
            .font(badgeFont)
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
    }

    /// Same frame as the standard badge so departure rows keep their column
    /// alignment when the setting flips.
    private var reducedBody: some View {
        HStack(spacing: 6 * scale) {
            Capsule(style: .continuous)
                .fill(routeColor)
                .frame(width: barWidth, height: size * scale)
            Text(routeShortName)
                .font(badgeFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
