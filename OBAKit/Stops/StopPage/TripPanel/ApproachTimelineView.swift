//
//  ApproachTimelineView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Vertical line-and-dot approach timeline: upstream stops leading to the
/// user's stop with a "bus here" marker at the vehicle's position. Live
/// trips only (§4.1).
///
/// Per the comp: a continuous connector line runs through the dots — gray
/// above the bus's position, route-colored from the bus down to the user's
/// stop. Stops strictly behind the bus are small filled gray dots with dimmed
/// names; the bus's stop and everything between it and the user are outlined
/// route-color dots; the user's stop is a larger filled route-color dot.
///
/// Dot sizes and line width scale with Dynamic Type via `@ScaledMetric`;
/// labels use text styles.
struct ApproachTimelineView: View {
    struct Row: Identifiable {
        let id: String       // stopID
        let name: String
        let isUserStop: Bool
        let isVehicleHere: Bool
        let isPassed: Bool   // at or behind the vehicle
    }

    let rows: [Row]
    let minutesAway: Int
    let routeColor: Color

    @ScaledMetric(relativeTo: .body) private var userDotSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var stopDotSize: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 2.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    connectorColumn(index: index, row: row)
                    Text(row.name)
                        .font(.subheadline.weight(row.isUserStop ? .heavy : .medium))
                        .foregroundStyle(row.isUserStop ? .primary : (isBehindBus(row) ? Color(uiColor: .tertiaryLabel) : .secondary))
                        .lineLimit(1)
                    if row.isUserStop {
                        Text(OBALoc("stop_page.timeline.your_stop", value: "· your stop", comment: "Marker on the user's stop in the approach timeline"))
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.isVehicleHere {
                        Label(String(format: OBALoc("stop_page.timeline.bus_here_fmt", value: "bus here · %dm away", comment: "Vehicle-position pill. %d is minutes to the user's stop."), minutesAway), systemImage: "bus.fill")
                            .font(.caption2.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(routeColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(routeColor.opacity(0.14), in: Capsule())
                    }
                }
                .frame(minHeight: 32)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Behind the bus" for styling: `isPassed` marks at-or-behind, but the
    /// bus's own row renders active (colored dot, undimmed name) per the comp.
    private func isBehindBus(_ row: Row) -> Bool {
        row.isPassed && !row.isVehicleHere
    }

    /// Color of the connector segment hanging BELOW the row at `index` (down
    /// to the next row): gray while still behind the bus, route color from the
    /// bus's stop onward.
    private func segmentColor(fromRowAt index: Int) -> Color {
        isBehindBus(rows[index]) ? Color(uiColor: .systemGray4) : routeColor
    }

    /// The dot with its two connector half-segments behind it. The top half
    /// continues the segment from the previous row; the bottom half starts
    /// this row's own segment; first/last rows leave their outer half clear.
    private func connectorColumn(index: Int, row: Row) -> some View {
        ZStack {
            VStack(spacing: 0) {
                (index > 0 ? segmentColor(fromRowAt: index - 1) : Color.clear)
                    .frame(width: lineWidth)
                    .frame(maxHeight: .infinity)
                (index < rows.count - 1 ? segmentColor(fromRowAt: index) : Color.clear)
                    .frame(width: lineWidth)
                    .frame(maxHeight: .infinity)
            }
            dot(for: row)
        }
        .frame(width: userDotSize)
    }

    @ViewBuilder
    private func dot(for row: Row) -> some View {
        if row.isUserStop {
            Circle()
                .fill(routeColor)
                .frame(width: userDotSize, height: userDotSize)
        } else if isBehindBus(row) {
            Circle()
                .fill(Color(uiColor: .systemGray3))
                .frame(width: stopDotSize, height: stopDotSize)
        } else {
            // Opaque interior so the connector line doesn't show through the
            // open ring.
            Circle()
                .strokeBorder(routeColor, lineWidth: lineWidth)
                .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                .frame(width: stopDotSize, height: stopDotSize)
        }
    }
}
