//
//  TripStopListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Every stop on the trip, as a line-and-dot timeline with arrival times.
///
/// Shares its visual language with `ApproachTimelineView` — gray behind the
/// vehicle, route color ahead, a filled dot carrying the transport glyph at the
/// vehicle's position — but not its code: that view windows to five stops and
/// renders an elision marker, both of which a full list must not do.
struct TripStopListView: View {
    let rows: [TripStopListModel.Row]
    let routeColor: Color
    let routeType: Route.RouteType
    let onSelect: (TripStopListModel.Row) -> Void

    var body: some View {
        // Lazy because a long trip runs to sixty-odd stops and only a handful
        // are ever on screen.
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                TripStopRow(
                    row: row,
                    isFirst: index == 0,
                    isLast: index == rows.count - 1,
                    segmentAboveIsSpent: index > 0 && rows[index - 1].isPassed,
                    routeColor: routeColor,
                    routeType: routeType,
                    onSelect: { onSelect(row) }
                )
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One stop. Its own `View` type so SwiftUI can skip rows whose values haven't
/// changed when the vehicle advances — on a sixty-stop trip a refresh moves two
/// rows, not all of them.
private struct TripStopRow: View {
    let row: TripStopListModel.Row
    let isFirst: Bool
    let isLast: Bool
    /// Whether the connector coming down into this row is behind the vehicle.
    /// A row can't work this out alone: the segment's color belongs to the stop
    /// above it, not to this one.
    let segmentAboveIsSpent: Bool
    let routeColor: Color
    let routeType: Route.RouteType
    let onSelect: () -> Void

    @Environment(\.obaFormatters) private var formatters

    @ScaledMetric(relativeTo: .body) private var stopDotSize: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var userDotSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var vehicleDotSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 2.5

    /// Dimmed once the bus is past. The vehicle's own stop stays active — it is
    /// where the rider's attention belongs.
    private var isBehind: Bool { row.isPassed && !row.isVehicleHere }

    var body: some View {
        HStack(spacing: 12) {
            connector
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    Spacer(minLength: 8)
                    time
                }
                .padding(.vertical, 11)
                // The rule stops short of the connector so the line reads as
                // continuous through the whole list.
                if !isLast {
                    Divider()
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var name: some View {
        Text(row.name)
            .font(.subheadline.weight(row.isUserStop ? .heavy : .regular))
            .foregroundStyle(isBehind ? Color(uiColor: .tertiaryLabel) : .primary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var time: some View {
        if let date = row.date {
            Text(formatters.timeFormatter.string(from: date))
                .font(.subheadline)
                .foregroundStyle(isBehind ? Color(uiColor: .tertiaryLabel) : .secondary)
                .monospacedDigit()
                // At accessibility sizes the row runs out of width and the HStack
                // was breaking this column mid-token — "6:04 PM" set as "6:04 P"
                // over "M". A clock time is one indivisible glyph run, so it takes
                // its intrinsic width and the stop name (which has two lines and
                // wraps on word boundaries) absorbs the shortfall instead.
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Connector

    private var connector: some View {
        ZStack {
            VStack(spacing: 0) {
                segment(isHidden: isFirst, isSpent: segmentAboveIsSpent)
                segment(isHidden: isLast, isSpent: row.isPassed)
            }
            dot
        }
        .frame(width: vehicleDotSize)
    }

    private func segment(isHidden: Bool, isSpent: Bool) -> some View {
        (isHidden ? Color.clear : (isSpent ? Color(uiColor: .systemGray4) : routeColor))
            .frame(width: lineWidth)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var dot: some View {
        if row.isVehicleHere {
            Circle()
                .fill(routeColor)
                .frame(width: vehicleDotSize, height: vehicleDotSize)
                .overlay {
                    Image(uiImage: Icons.transportIcon(from: routeType))
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: vehicleDotSize * 0.55, height: vehicleDotSize * 0.55)
                }
        } else if row.isUserStop {
            Circle()
                .fill(routeColor)
                .frame(width: userDotSize, height: userDotSize)
        } else if isBehind {
            Circle()
                .fill(Color(uiColor: .systemGray3))
                .frame(width: stopDotSize, height: stopDotSize)
        } else {
            // Opaque interior so the connector doesn't show through the ring.
            Circle()
                .strokeBorder(routeColor, lineWidth: lineWidth)
                .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                .frame(width: stopDotSize, height: stopDotSize)
        }
    }

    // MARK: - Accessibility

    /// VoiceOver can't perceive dot size or dimming, so every distinction the
    /// timeline draws has to be said.
    private var accessibilityLabel: String {
        var clauses = [row.name]

        if let date = row.date {
            clauses.append(formatters.timeFormatter.string(from: date))
        }
        if row.isVehicleHere {
            clauses.append(OBALoc("trip_page.stop_list.a11y_vehicle_here", value: "vehicle is here", comment: "VoiceOver clause on the stop the vehicle is currently at."))
        } else if isBehind {
            clauses.append(OBALoc("trip_page.stop_list.a11y_passed", value: "already passed", comment: "VoiceOver clause on a stop the vehicle has already served."))
        }
        if row.isUserStop {
            clauses.append(OBALoc("trip_page.stop_list.a11y_your_stop", value: "your stop", comment: "VoiceOver clause on the rider's own stop."))
        }
        if row.isTerminal {
            clauses.append(OBALoc("trip_page.stop_list.a11y_terminal", value: "last stop", comment: "VoiceOver clause on the final stop of the trip."))
        }

        return clauses.joined(separator: ", ")
    }
}
