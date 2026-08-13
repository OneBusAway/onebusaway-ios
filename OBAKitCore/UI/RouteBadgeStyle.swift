//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// The shared visual policy for route badges: which text color to draw over
/// the route color (agency `route_text_color` when it clears the WCAG bar,
/// else computed black/white) and whether the fill keeps its gradient. One
/// home so the stop page's badge and OBAKitCore's public `RouteBadgeView`
/// (bookmark cards, trip Live Activity) cannot drift.
public enum RouteBadgeStyle {

    /// AA (4.5:1) for the standard presentation; AAA (7:1) once the user
    /// asks the system for more contrast.
    private static func minimumRatio(for contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? 7.0 : 4.5
    }

    public static func textColor(routeColor: Color, routeTextColor: Color?, contrast: ColorSchemeContrast) -> Color {
        let background = UIColor(routeColor)
        let preferred = routeTextColor.map { UIColor($0) }
        return Color(uiColor: background.badgeTextColor(preferring: preferred, minimumRatio: minimumRatio(for: contrast)))
    }

    /// The gradient's luminance ramp is a small, intentional deviation from
    /// the flat color the ratio is computed against; Increase Contrast goes
    /// flat so the strict 7:1 tier has no ambiguity.
    public static func backgroundStyle(routeColor: Color, contrast: ColorSchemeContrast) -> AnyShapeStyle {
        contrast == .increased ? AnyShapeStyle(routeColor) : AnyShapeStyle(routeColor.gradient)
    }
}
