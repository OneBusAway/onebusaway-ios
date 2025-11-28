//
//  StopAnnotationIconView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A pure SwiftUI view that renders stop annotation icons matching the visual style of StopIconFactory.
/// Displays a rounded square with transport icon, gradient background, border, and directional arrow.
struct StopAnnotationIconView: View {
    let routeType: Route.RouteType
    let direction: Direction
    let isBookmarked: Bool

    // MARK: - Constants (matching StopIconFactory)

    /// Total icon size including arrow gutter
    private let iconSize: CGFloat = 48

    /// Outer gutter for directional arrows
    private let arrowTrackSize: CGFloat = 8

    /// Line width for the arrow border
    private let arrowStroke: CGFloat = 1

    /// Stroke width for the main icon border
    private let borderWidth: CGFloat = 2

    /// Opacity of the background gradient
    private let backgroundAlpha: CGFloat = 0.9

    /// Corner radius of the rounded rectangle
    private let cornerRadius: CGFloat = ThemeMetrics.stopAnnotationCornerRadius

    /// Inset for the transport icon inside the rounded rect
    private let iconInset: CGFloat = ThemeMetrics.stopAnnotationIconInset

    // MARK: - Computed Properties

    /// Size of the inner rounded rectangle (excluding arrow gutter)
    private var innerRectSize: CGFloat {
        iconSize - (arrowTrackSize * 2)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Directional arrow (behind the main icon)
            if direction != .unknown {
                DirectionalArrowShape(direction: direction)
                    .fill(arrowFillColor)
                    .overlay(
                        DirectionalArrowShape(direction: direction)
                            .stroke(strokeColor, lineWidth: arrowStroke)
                    )
            }

            // Main rounded rectangle with gradient background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundGradient)
                .opacity(backgroundAlpha)
                .frame(width: innerRectSize, height: innerRectSize)

            // Border stroke
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(strokeColor, lineWidth: borderWidth)
                .frame(width: innerRectSize, height: innerRectSize)

            // Transport icon
            transportIconImage
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(transportIconColor)
                .frame(
                    width: innerRectSize - (iconInset * 2),
                    height: innerRectSize - (iconInset * 2)
                )
        }
        .frame(width: iconSize, height: iconSize)
    }

    // MARK: - Colors

    private var fillColor: Color {
        if isBookmarked {
            return Color(ThemeColors.shared.brand)
        }
        return Color(ThemeColors.shared.stopAnnotationFillColor)
    }

    private var strokeColor: Color {
        Color(ThemeColors.shared.stopAnnotationStrokeColor)
    }

    private var arrowFillColor: Color {
        Color(ThemeColors.shared.stopArrowFillColor)
    }

    private var transportIconColor: Color {
        isBookmarked ? .white : Color(ThemeColors.shared.label)
    }

    private var backgroundGradient: LinearGradient {
        let baseColor = fillColor
        // Lighten the top color by 25% to match StopIconFactory
        let lightenedColor = Color(UIColor(baseColor).lighten(by: 0.25))

        return LinearGradient(
            colors: [lightenedColor, baseColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Transport Icon

    private var transportIconImage: Image {
        let imageName: String
        switch routeType {
        case .lightRail:
            imageName = "lightRailTransport"
        case .subway, .rail:
            imageName = "trainTransport"
        case .ferry:
            imageName = "ferryTransport"
        default:
            imageName = "busTransport"
        }
        return Image(imageName, bundle: .OBAKit)
    }
}

// MARK: - Convenience Initializer

extension StopAnnotationIconView {
    /// Creates a stop annotation icon view from a Stop model
    init(stop: Stop, isBookmarked: Bool = false) {
        self.routeType = stop.prioritizedRouteTypeForDisplay
        self.direction = stop.direction
        self.isBookmarked = isBookmarked
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    static var OBAKit: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: Icons.self)
        #endif
    }
}
