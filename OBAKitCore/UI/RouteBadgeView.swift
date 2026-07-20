//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Rounded-square route identity badge. Public so the widget extension can use it.
///
/// Text color is WCAG-aware (same decision as the stop page's internal
/// `RouteBadgeView`): agency text color when it clears the threshold, else
/// computed black/white; Increase Contrast flattens the gradient and raises
/// the threshold to 7:1. Note: in `accented`/`vibrant` widget rendering modes
/// the system tints everything and this logic is moot; it matters in
/// `fullColor` rendering.
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
