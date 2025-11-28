//
//  TripSegmentIndicator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// SwiftUI equivalent of TripSegmentView - draws the timeline indicator for trip stops
struct TripSegmentIndicator: View {
    let isUserDestination: Bool
    let isCurrentVehicleLocation: Bool
    let routeType: Route.RouteType
    var adjacentTripOrder: AdjacentTripOrder?

    private let lineWidth: CGFloat = 1.0
    private let circleSize: CGFloat = 30.0
    private let cornerRadius: CGFloat = 8.0

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let midY = size.height / 2
            let halfCircle = circleSize / 2

            // Set the line color
            let lineColor = Color.accentColor

            switch adjacentTripOrder {
            case .next:
                // Draw only top line (connecting to previous stop)
                drawLine(context: context, from: CGPoint(x: midX, y: 0), to: CGPoint(x: midX, y: midY), color: lineColor)

            case .previous:
                // Draw only bottom line (connecting to next stop)
                drawLine(context: context, from: CGPoint(x: midX, y: midY), to: CGPoint(x: midX, y: size.height), color: lineColor)

            case .none:
                // Draw full segment with squircle
                // Top line
                drawLine(context: context, from: CGPoint(x: midX, y: 0), to: CGPoint(x: midX, y: midY - halfCircle), color: lineColor)

                // Squircle (rounded rect)
                let squircleRect = CGRect(
                    x: midX - halfCircle,
                    y: midY - halfCircle,
                    width: circleSize,
                    height: circleSize
                )
                let squirclePath = RoundedRectangle(cornerRadius: cornerRadius).path(in: squircleRect)
                context.stroke(squirclePath, with: .color(lineColor), lineWidth: lineWidth)

                // Vehicle icon inside squircle (if current vehicle location)
                if isCurrentVehicleLocation {
                    let iconRect = squircleRect.insetBy(dx: 5, dy: 5)
                    let iconName = systemImageName(for: routeType)
                    if let resolved = context.resolveSymbol(id: "vehicleIcon") {
                        context.draw(resolved, in: iconRect)
                    }
                }

                // Bottom line
                drawLine(context: context, from: CGPoint(x: midX, y: midY + halfCircle), to: CGPoint(x: midX, y: size.height), color: lineColor)

                // User destination badge
                if isUserDestination {
                    drawUserDestinationBadge(context: context, centerX: midX, centerY: midY, halfCircle: halfCircle)
                }
            }
        } symbols: {
            // Vehicle icon symbol
            Image(systemName: systemImageName(for: routeType))
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .tag("vehicleIcon")
        }
    }

    private func drawLine(context: GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawUserDestinationBadge(context: GraphicsContext, centerX: CGFloat, centerY: CGFloat, halfCircle: CGFloat) {
        // Draw a small badge in the bottom-right of the squircle
        let badgeSize = halfCircle + lineWidth
        let badgeRect = CGRect(
            x: centerX - lineWidth,
            y: centerY - lineWidth,
            width: badgeSize,
            height: badgeSize
        )

        // Fill the badge
        let badgePath = RoundedRectangle(cornerRadius: cornerRadius / 2).path(in: badgeRect)
        context.fill(badgePath, with: .color(Color.accentColor))

        // Draw walking icon
        if let walkingSymbol = context.resolveSymbol(id: "walkingIcon") {
            let iconRect = badgeRect.insetBy(dx: 2, dy: 2)
            context.draw(walkingSymbol, in: iconRect)
        }
    }

    private func systemImageName(for routeType: Route.RouteType) -> String {
        switch routeType {
        case .lightRail:
            return "tram.fill"
        case .subway:
            return "tram.fill.tunnel"
        case .rail:
            return "train.side.front.car"
        case .bus:
            return "bus.fill"
        case .ferry:
            return "ferry.fill"
        case .cableCar:
            return "cablecar.fill"
        case .gondola:
            return "cablecar.fill"
        case .funicular:
            return "tram.fill"
        default:
            return "bus.fill"
        }
    }
}

/// A simpler version of TripSegmentIndicator for use in SwiftUI List rows
struct SimpleTripSegmentIndicator: View {
    let isUserDestination: Bool
    let isCurrentVehicleLocation: Bool
    let routeType: Route.RouteType
    var isFirst: Bool = false
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top connecting line
            if !isFirst {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxHeight: .infinity)
            }

            // Center indicator
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 24, height: 24)

                if isCurrentVehicleLocation {
                    Image(systemName: systemImageName(for: routeType))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }

                if isUserDestination {
                    // Small walking badge
                    Image(systemName: "figure.walk")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: 8, y: 8)
                }
            }

            // Bottom connecting line
            if !isLast {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 32)
    }

    private func systemImageName(for routeType: Route.RouteType) -> String {
        switch routeType {
        case .lightRail: return "tram.fill"
        case .subway: return "tram.fill.tunnel"
        case .rail: return "train.side.front.car"
        case .bus: return "bus.fill"
        case .ferry: return "ferry.fill"
        case .cableCar, .gondola: return "cablecar.fill"
        default: return "bus.fill"
        }
    }
}

#if DEBUG
struct TripSegmentIndicator_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            VStack {
                SimpleTripSegmentIndicator(
                    isUserDestination: false,
                    isCurrentVehicleLocation: false,
                    routeType: .bus
                )
                .frame(height: 60)
                Text("Standard")
                    .font(.caption)
            }

            VStack {
                SimpleTripSegmentIndicator(
                    isUserDestination: true,
                    isCurrentVehicleLocation: false,
                    routeType: .bus
                )
                .frame(height: 60)
                Text("User Dest")
                    .font(.caption)
            }

            VStack {
                SimpleTripSegmentIndicator(
                    isUserDestination: false,
                    isCurrentVehicleLocation: true,
                    routeType: .bus
                )
                .frame(height: 60)
                Text("Vehicle")
                    .font(.caption)
            }

            VStack {
                SimpleTripSegmentIndicator(
                    isUserDestination: true,
                    isCurrentVehicleLocation: true,
                    routeType: .bus
                )
                .frame(height: 60)
                Text("Both")
                    .font(.caption)
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
