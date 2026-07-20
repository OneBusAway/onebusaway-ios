//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge. Public so the widget extension can use it.
///
/// Text color and fill are decided by `RouteBadgeStyle` (WCAG-aware; see
/// docs/superpowers/specs/2026-07-20-stop-ui-accessibility-design.md).
/// Currently consumed by the trip Live Activity and in-app bookmark cards,
/// neither of which is subject to widget `accented`/`vibrant` tinting; if
/// this badge is ever placed in a timeline widget, the color logic only
/// matters in `fullColor` rendering. Neither current consumer passes
/// `routeTextColor`, so the agency-color path is exercised only by the stop
/// page's separate badge.
public struct RouteBadgeView: View {
    public let routeShortName: String
    public let routeColor: Color
    public var routeTextColor: Color?
    public var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorSchemeContrast) private var contrast

    public init(routeShortName: String, routeColor: Color, routeTextColor: Color? = nil, size: CGFloat = 44) {
        self.routeShortName = routeShortName
        self.routeColor = routeColor
        self.routeTextColor = routeTextColor
        self.size = size
    }

    private var resolvedTextColor: Color {
        RouteBadgeStyle.textColor(routeColor: routeColor, routeTextColor: routeTextColor, contrast: contrast)
    }

    private var backgroundStyle: AnyShapeStyle {
        RouteBadgeStyle.backgroundStyle(routeColor: routeColor, contrast: contrast)
    }

    public var body: some View {
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(resolvedTextColor)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
