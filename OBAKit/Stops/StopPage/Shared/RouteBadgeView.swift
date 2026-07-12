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
///
/// Rendered as a gradient of the route color with a glossy rim, plus the real
/// Liquid Glass foreground treatment on OS versions that have it.
struct RouteBadgeView: View {
    let routeShortName: String
    let routeColor: Color
    var size: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * scale * 0.28, style: .continuous)
        Text(routeShortName)
            .font(.system(size: (routeShortName.count <= 2 ? 18 : 13) * scale, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size * scale, height: size * scale)
            .background(routeColor.gradient, in: shape)
            // Glossy rim highlight — carries the glass feel on iOS 18–25 too.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .modifier(BadgeGlassEffect(shape: shape))
            .shadow(color: routeColor.opacity(0.3), radius: 3, y: 1)
            .accessibilityHidden(true) // route name is in the row's combined label
    }
}

/// Applies the Liquid Glass foreground treatment over the badge's gradient on
/// iOS 26+ (`.clear` so the route color stays saturated underneath); a no-op
/// on earlier versions, where the gradient + rim highlight stand alone.
private struct BadgeGlassEffect<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content
        }
    }
}
