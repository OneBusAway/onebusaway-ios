//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Rounded-square route identity badge — the only place route color appears in
/// the departure list rows; the trip panel separately uses it for the vehicle
/// glyph and approach timeline. The stop-page-rethink spec's §4.3 still holds:
/// route color never tints countdowns or adherence text.
///
/// Text color and fill are decided by `RouteBadgeStyle` (WCAG-aware; see
/// docs/superpowers/specs/2026-07-20-stop-ui-accessibility-design.md).
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
    @Environment(\.layoutDirection) private var layoutDirection

    private var resolvedTextColor: Color {
        RouteBadgeStyle.textColor(routeColor: routeColor, routeTextColor: routeTextColor, contrast: contrast)
    }

    private var backgroundStyle: AnyShapeStyle {
        RouteBadgeStyle.backgroundStyle(routeColor: routeColor, contrast: contrast)
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
    /// alignment when the setting flips. The thin color bar is drawn as a
    /// leading overlay offset into the row's leading gap (negative leading), so
    /// the route name keeps the full badge width instead of being squeezed by
    /// the bar + spacing — otherwise `minimumScaleFactor` shrinks it to an
    /// illegible size for names like "C Line".
    private var reducedBody: some View {
        // `offset(x:)` is a physical shift, so the sign is flipped for RTL: the
        // bar must move outward past the (right-hand) leading edge, not inward
        // over the text.
        let barOffset = (layoutDirection == .rightToLeft ? 1 : -1) * (barWidth + 6 * scale)
        return Text(routeShortName)
            .font(badgeFont)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale, alignment: .leading)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(routeColor)
                    .frame(width: barWidth, height: size * scale)
                    .offset(x: barOffset)
            }
    }
}
