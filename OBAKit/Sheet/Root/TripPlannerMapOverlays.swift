//
//  TripPlannerMapOverlays.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Trip planner map content: the planned route polylines and the trip's annotations
/// (start, end, intermediate stops).
///
/// A free function rather than inline map content because `MapPanelRootView.body`
/// has already exceeded Swift's type-check budget once.
///
/// The routes and annotations are insertion-ordered on purpose: OTPKit draws a white
/// halo under each leg and then the coloured line on top, so the order it adds them
/// in *is* the z-order. Annotations (drawn last) sit on top of all routes.
@MapContentBuilder
func tripPlannerMapContent(
    for display: TripPlannerMapDisplayModel
) -> some MapContent {
    // Draw routes in insertion order to preserve z-order (halos first, then
    // coloured lines on top).
    ForEach(display.routes) { route in
        MapPolyline(
            MKPolyline(coordinates: route.coordinates, count: route.coordinates.count)
        )
        .stroke(
            route.color,
            style: StrokeStyle(
                lineWidth: route.lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: (route.dashPattern ?? []).map { CGFloat($0.doubleValue) }
            )
        )
    }

    // Tagged with OTPKit's own opaque identifier so a tap routes back to OTPKit
    // verbatim — the panel never interprets it. Same tagging shape the ambient
    // stop and rental layers use, so all three share one `selection` binding.
    //
    // The card hangs above its coordinate rather than centred on it: a stop pin
    // at the same spot draws on top of the card and would hide the middle of
    // the name (#1753). The anchor sits below the card, so the card's frame —
    // and its tap target — stays clear of the pin.
    ForEach(display.annotations) { annotation in
        Annotation(
            "",
            coordinate: annotation.coordinate,
            anchor: TripPlannerCardMetrics.anchor(cardHeight: TripPlannerCardMetrics.size(for: annotation).height)
        ) {
            tripAnnotationContent(for: annotation)
        }
        .tag(MapPinSelection.tripPlannerAnnotation(annotation.identifier))
    }
}

/// Builds the visual representation of a trip annotation pin.
///
/// Fonts and padding come from `TripPlannerCardMetrics`, which measures the
/// same card to anchor it, so drawing and measuring can't drift apart.
@ViewBuilder
private func tripAnnotationContent(
    for annotation: TripPlannerMapDisplayModel.Annotation
) -> some View {
    VStack(spacing: 0) {
        // Route badge (if this annotation has transit route info).
        if let routeName = annotation.routeName,
           let backgroundColor = annotation.routeBackgroundColor,
           let textColor = annotation.routeTextColor {
            Text(routeName)
                .font(Font(Metrics.badgeFont))
                .lineLimit(1)
                .foregroundColor(Color(textColor))
                .padding(.vertical, Metrics.badgeVerticalPadding)
                .padding(.horizontal, Metrics.badgeHorizontalPadding)
                .background(Color(backgroundColor))
                .cornerRadius(3)
                .padding(.bottom, Metrics.badgeSpacing)
        }

        // Primary title.
        Text(annotation.title)
            .font(Font(Metrics.titleFont))
            .lineLimit(1)
            .foregroundColor(Color(uiColor: .label))

        // Optional subtitle.
        if let subtitle = annotation.subtitle {
            Text(subtitle)
                .font(Font(Metrics.subtitleFont))
                .lineLimit(1)
                .foregroundColor(Color(uiColor: .secondaryLabel))
        }
    }
    .padding(Metrics.padding)
    .background(Color(uiColor: .systemBackground))
    .cornerRadius(6)
    .shadow(radius: 2)
}

private typealias Metrics = TripPlannerCardMetrics

/// The size and placement of a trip planner card (`tripAnnotationContent`).
///
/// Cards hang above their coordinate, a pin's half-height plus the label gap
/// up, the way an `.above` stop label hangs off its pin. A stop pin at the same
/// coordinate then sits just below the card instead of on top of it. Stop
/// labels treat the resulting rects as obstacles (`MapStopLabelLayout`).
///
/// The fonts are fixed sizes, as they were before, so the card can be measured
/// here without a view.
enum TripPlannerCardMetrics {
    static let titleFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
    static let subtitleFont = UIFont.systemFont(ofSize: 10)
    static let badgeFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
    static let padding: CGFloat = 6
    static let badgeVerticalPadding: CGFloat = 2
    static let badgeHorizontalPadding: CGFloat = 4
    static let badgeSpacing: CGFloat = 4

    /// How far above the coordinate the card's bottom edge sits.
    static func reach(pinSize: CGFloat = ThemeMetrics.defaultMapAnnotationSize, gap: CGFloat = MapStopLabelLayout.gap) -> CGFloat {
        pinSize / 2 + gap
    }

    static func size(for annotation: TripPlannerMapDisplayModel.Annotation) -> CGSize {
        // The badge only draws with both of its colors.
        let hasBadge = annotation.routeBackgroundColor != nil && annotation.routeTextColor != nil
        return size(title: annotation.title, subtitle: annotation.subtitle, routeName: hasBadge ? annotation.routeName : nil)
    }

    static func size(title: String, subtitle: String?, routeName: String?) -> CGSize {
        func measure(_ text: String, _ font: UIFont) -> CGSize {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            return CGSize(width: ceil(width), height: ceil(font.lineHeight))
        }
        var width = measure(title, titleFont).width
        var height = measure(title, titleFont).height
        if let subtitle {
            let line = measure(subtitle, subtitleFont)
            width = max(width, line.width)
            height += line.height
        }
        if let routeName {
            let badge = measure(routeName, badgeFont)
            width = max(width, badge.width + badgeHorizontalPadding * 2)
            height += badge.height + badgeVerticalPadding * 2 + badgeSpacing
        }
        return CGSize(width: width + padding * 2, height: height + padding * 2)
    }

    /// The point on the card that MapKit places on the coordinate: centred
    /// horizontally, and `reach` below the card's bottom edge.
    static func anchor(cardHeight: CGFloat, pinSize: CGFloat = ThemeMetrics.defaultMapAnnotationSize, gap: CGFloat = MapStopLabelLayout.gap) -> UnitPoint {
        guard cardHeight > 0 else { return .bottom }
        return UnitPoint(x: 0.5, y: 1 + reach(pinSize: pinSize, gap: gap) / cardHeight)
    }

    /// Where a card of `size` draws when its coordinate projects to `center`.
    static func rect(size: CGSize, at center: CGPoint, pinSize: CGFloat = ThemeMetrics.defaultMapAnnotationSize, gap: CGFloat = MapStopLabelLayout.gap) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - reach(pinSize: pinSize, gap: gap) - size.height,
            width: size.width,
            height: size.height
        )
    }
}
