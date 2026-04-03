//
//  TripStopRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - TripRouteSegment

enum TripRouteSegment {
    case first          // line only below the dot
    case middle         // line above and below
    case last           // line only above the dot
    case adjacentPrev   // "Starts as …" — line below only, no dot
    case adjacentNext   // "Continues as …" — line above only, no dot
}

// MARK: - TripStopRowViewModel

struct TripStopRowViewModel: Identifiable, Equatable {
    let id: String
    let stopName: String
    let arrivalTime: String
    let segment: TripRouteSegment
    let routeType: Route.RouteType
    let isCurrentVehicleLocation: Bool
    let isUserDestination: Bool
    let isAdjacentTrip: Bool
    let adjacentTripLabel: String?
    var isPast: Bool = false
    /// Positive = late, negative = early, nil = on-time / scheduled.
    var delayMinutes: Int? = nil
}

// MARK: - TripStopRow

struct TripStopRow: View {
    let viewModel: TripStopRowViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isAccessibilitySize: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        // Adjacent trip rows get a distinct compact layout
        if viewModel.isAdjacentTrip {
            adjacentTripRow
        } else {
            stopRow
        }
    }

    // MARK: - Adjacent trip row (Starts as / Continues as)

    private var adjacentTripRow: some View {
        HStack(alignment: .center, spacing: 0) {
            TripSegmentCanvas(
                segment: viewModel.segment,
                routeType: viewModel.routeType,
                isCurrentVehicleLocation: false,
                isUserDestination: false,
                isPast: false
            )
            .frame(width: 56)
            .frame(maxHeight: .infinity)

            HStack(spacing: 4) {
                if let label = viewModel.adjacentTripLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(viewModel.stopName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.systemGreen))
                    .lineLimit(1)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(.systemGreen).opacity(0.7))
            }
            .padding(.leading, 2)
            .padding(.trailing, 16)
            .padding(.vertical, 10)

            Spacer()
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewModel.adjacentTripLabel ?? "") \(viewModel.stopName)")
    }

    // MARK: - Normal stop row

    private var stopRow: some View {
        HStack(alignment: .center, spacing: 0) {
            TripSegmentCanvas(
                segment: viewModel.segment,
                routeType: viewModel.routeType,
                isCurrentVehicleLocation: viewModel.isCurrentVehicleLocation,
                isUserDestination: viewModel.isUserDestination,
                isPast: viewModel.isPast
            )
            .frame(width: 56)
            .frame(maxHeight: .infinity)

            Group {
                if isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        stopNameText
                        HStack(spacing: 6) { timeText; delayText }
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        stopNameText
                        Spacer(minLength: 8)
                        HStack(spacing: 6) { delayText; timeText }
                    }
                }
            }
            .padding(.leading, 2)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
        .frame(minHeight: 58)
        .opacity(viewModel.isPast ? 0.38 : 1.0)
        .overlay(alignment: .leading) {
            if viewModel.isCurrentVehicleLocation {
                Rectangle()
                    .fill(Color(.systemGreen))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(a11yValue ?? "")
        .accessibilityAddTraits(viewModel.isCurrentVehicleLocation ? .isSelected : [])
    }

    // MARK: - Subviews

    private var stopNameText: some View {
        Text(viewModel.stopName)
            .font(.subheadline.weight(viewModel.isCurrentVehicleLocation ? .bold : .medium))
            .foregroundStyle(viewModel.isCurrentVehicleLocation ? Color(.systemGreen) : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(2)
    }

    private var timeText: some View {
        Text(viewModel.arrivalTime)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize()
    }

    @ViewBuilder
    private var delayText: some View {
        if let delay = viewModel.delayMinutes, delay != 0, !viewModel.isPast {
            Text(delay > 0 ? "+\(delay)m" : "\(delay)m")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delay > 0 ? .red : Color(.systemGreen))
                .monospacedDigit()
                .fixedSize()
        }
    }

    // MARK: - Accessibility

    private var a11yLabel: String {
        [viewModel.stopName, viewModel.arrivalTime].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var a11yValue: String? {
        var flags: [String] = []
        if viewModel.isUserDestination {
            flags.append(OBALoc("trip_stop.user_destination.accessibility_label",
                                value: "Your destination",
                                comment: "Voiceover: this stop is the user's destination"))
        }
        if viewModel.isCurrentVehicleLocation {
            flags.append(OBALoc("trip_stop.vehicle_location.accessibility_label",
                                value: "Vehicle is here",
                                comment: "Voiceover: the vehicle is currently at this stop"))
        }
        if viewModel.isPast {
            flags.append(OBALoc("trip_stop.past_stop.accessibility_label",
                                value: "Already passed",
                                comment: "Voiceover: this stop has already been passed"))
        }
        if let delay = viewModel.delayMinutes, delay != 0, !viewModel.isPast {
            flags.append(delay > 0 ? "\(delay) minutes late" : "\(abs(delay)) minutes early")
        }
        return flags.isEmpty ? nil : flags.joined(separator: ", ")
    }
}

// MARK: - TripSegmentCanvas

struct TripSegmentCanvas: View {
    let segment: TripRouteSegment
    let routeType: Route.RouteType
    let isCurrentVehicleLocation: Bool
    let isUserDestination: Bool
    var isPast: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var activeColor: Color { Color(.systemGreen) }
    private var lineColor: Color { isPast ? activeColor.opacity(0.28) : activeColor }
    private let lineWidth: CGFloat = 4
    private let squareSize: CGFloat = 26
    private let cornerRadius: CGFloat = 7

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let half = squareSize / 2

            if drawsTopLine {
                var p = Path()
                p.move(to: CGPoint(x: cx, y: 0))
                p.addLine(to: CGPoint(x: cx, y: cy - half))
                ctx.stroke(p, with: .color(lineColor), lineWidth: lineWidth)
            }
            if drawsBottomLine {
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy + half))
                p.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(p, with: .color(lineColor), lineWidth: lineWidth)
            }

            guard !isAdjacentRow else { return }

            let rect = CGRect(x: cx - half, y: cy - half, width: squareSize, height: squareSize)
            let squarePath = Path(roundedRect: rect, cornerRadius: cornerRadius)

            if isCurrentVehicleLocation {
                ctx.fill(squarePath, with: .color(activeColor))
                let icon = ctx.resolve(Image(systemName: transportIcon).symbolRenderingMode(.hierarchical))
                ctx.draw(icon, in: rect.insetBy(dx: 5, dy: 5))
            } else {
                let bg: Color = colorScheme == .dark ? Color(.systemBackground) : .white
                ctx.fill(squarePath, with: .color(bg))
                ctx.stroke(squarePath, with: .color(lineColor), lineWidth: lineWidth - 1)

                if isUserDestination {
                    let bs: CGFloat = squareSize * 0.5
                    let br = CGRect(x: rect.maxX - bs + 3, y: rect.maxY - bs + 3, width: bs, height: bs)
                    ctx.fill(Path(roundedRect: br, cornerRadius: 4), with: .color(activeColor))
                    let walk = ctx.resolve(Image(systemName: "figure.walk").symbolRenderingMode(.hierarchical))
                    ctx.draw(walk, in: br.insetBy(dx: 2, dy: 2))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var isAdjacentRow: Bool   { segment == .adjacentPrev || segment == .adjacentNext }
    private var drawsTopLine: Bool    { segment != .first && segment != .adjacentPrev }
    private var drawsBottomLine: Bool { segment != .last && segment != .adjacentNext }

    private var transportIcon: String {
        switch routeType {
        case .bus:      return "bus.fill"
        case .rail:     return "tram.fill"
        case .subway:   return "tram.fill"
        case .ferry:    return "ferry.fill"
        case .cableCar: return "cablecar.fill"
        default:        return "bus.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
private let _previewStops: [TripStopRowViewModel] = [
    .init(id: "1", stopName: "WOODROW RD/VINELAND AV",  arrivalTime: "9:45 PM", segment: .first,  routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: true,  delayMinutes: nil),
    .init(id: "2", stopName: "WOODROW RD/HOLCOMB AV",   arrivalTime: "9:46 PM", segment: .middle, routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: true,  delayMinutes: nil),
    .init(id: "3", stopName: "ARDEN AV/WOODROW RD",     arrivalTime: "9:47 PM", segment: .middle, routeType: .bus, isCurrentVehicleLocation: true,  isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: 3),
    .init(id: "4", stopName: "ARDEN AV/HAMPTON GREEN",  arrivalTime: "9:48 PM", segment: .middle, routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: false, isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: 3),
    .init(id: "5", stopName: "ARTHUR KILL RD/ARDEN AV", arrivalTime: "9:50 PM", segment: .last,   routeType: .bus, isCurrentVehicleLocation: false, isUserDestination: true,  isAdjacentTrip: false, adjacentTripLabel: nil, isPast: false, delayMinutes: -1),
]

#Preview("Stop Rows — dark") {
    List(_previewStops) { stop in
        TripStopRow(viewModel: stop)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color(.systemBackground))
    }
    .listStyle(.plain)
    .preferredColorScheme(.dark)
}
#endif
