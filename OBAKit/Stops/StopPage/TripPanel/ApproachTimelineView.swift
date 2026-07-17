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
/// user's stop with a bus-glyph dot marking the vehicle's position. Live
/// trips only (§4.1).
///
/// Per the comp: a continuous connector line runs through the dots — gray
/// above the bus's position, route-colored from the bus down to the user's
/// stop. Stops strictly behind the bus are small filled gray dots with dimmed
/// names; the vehicle's stop is a filled route-color dot containing the bus
/// glyph; stops between it and the user are outlined route-color dots; the
/// user's stop is a larger filled route-color dot.
///
/// Dot sizes and line width scale with Dynamic Type via `@ScaledMetric`;
/// labels use text styles.
struct ApproachTimelineView: View {
    struct Row: Identifiable {
        /// Position-qualified, not the bare stop ID: a loop route can put the same
        /// stop in the window twice, and duplicate `ForEach` identities collapse
        /// the rows.
        let id: String
        let name: String
        let isUserStop: Bool
        let isVehicleHere: Bool
        let isPassed: Bool   // at or behind the vehicle
    }

    let rows: [Row]
    let minutesAway: Int
    let routeColor: Color
    /// Drives the glyph inside the vehicle-position dot (bus, light rail, …).
    let routeType: Route.RouteType
    /// Stops elided between the vehicle's row (`rows[0]`) and `rows[1]` when
    /// the vehicle is further back than the window (§4.1). When > 0, a
    /// zig-zag gap row labeled with the count renders between them.
    let skippedStopCount: Int

    @ScaledMetric(relativeTo: .body) private var userDotSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var stopDotSize: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var busDotSize: CGFloat = 22
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
                }
                .frame(minHeight: 32)

                if index == 0 && skippedStopCount > 0 {
                    gapRow
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The elision marker between the vehicle's stop and the stops nearest
    /// the user: a zig-zag continuation of the connector line with the
    /// skipped-stop count alongside.
    private var gapRow: some View {
        HStack(spacing: 12) {
            ZigZagLine()
                .stroke(routeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: busDotSize)
            Text(skippedStopsLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(minHeight: 32)
    }

    private var skippedStopsLabel: String {
        String(format: OBALoc("stop_page.timeline.skipped_stops_fmt", value: "%d stops", comment: "Gap marker in the approach timeline. %d is the number of elided stops between the vehicle and the stops shown. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."), skippedStopCount)
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
        .frame(width: busDotSize)
    }

    @ViewBuilder
    private func dot(for row: Row) -> some View {
        if row.isVehicleHere {
            // The vehicle's position: the mode-appropriate transport glyph
            // rides inside the dot itself rather than in a trailing pill.
            Circle()
                .fill(routeColor)
                .frame(width: busDotSize, height: busDotSize)
                .overlay {
                    Image(uiImage: Icons.transportIcon(from: routeType))
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: busDotSize * 0.55, height: busDotSize * 0.55)
                }
                .accessibilityLabel(String(format: OBALoc("stop_page.timeline.vehicle_here_fmt", value: "vehicle here · %dm away", comment: "Vehicle-position marker. %d is minutes to the user's stop."), minutesAway))
        } else if row.isUserStop {
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

/// Vertical zig-zag connector segment for the timeline's gap row: enters at
/// the top center and exits at the bottom center so it lines up with the
/// straight connector halves above and below.
nonisolated private struct ZigZagLine: Shape {
    func path(in rect: CGRect) -> Path {
        let amplitude = min(rect.width / 2, 5)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - amplitude, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.midX + amplitude, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.midX - amplitude, y: rect.minY + rect.height * 0.8))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
