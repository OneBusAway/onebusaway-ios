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
/// trips only (§4.1). Stops at/behind the bus are gray, stops between bus
/// and user use the route color.
///
/// Dot sizes scale with Dynamic Type via `@ScaledMetric`; labels use text
/// styles (standing amendment 1).
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

    @ScaledMetric(relativeTo: .body) private var userDotSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var stopDotSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(row.isPassed ? Color(uiColor: .quaternaryLabel) : routeColor, lineWidth: 2.5)
                        .background(Circle().fill(row.isUserStop ? routeColor : Color.clear))
                        .frame(width: row.isUserStop ? userDotSize : stopDotSize,
                               height: row.isUserStop ? userDotSize : stopDotSize)
                    Text(row.name)
                        .font(.subheadline.weight(row.isUserStop ? .heavy : .medium))
                        .foregroundStyle(row.isUserStop ? .primary : (row.isPassed ? Color(uiColor: .tertiaryLabel) : .secondary))
                        .lineLimit(1)
                    if row.isUserStop {
                        Text(OBALoc("stop_page.timeline.your_stop", value: "· your stop", comment: "Marker on the user's stop in the approach timeline"))
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.isVehicleHere {
                        Label(String(format: OBALoc("stop_page.timeline.bus_here_fmt", value: "bus here · %dm away", comment: "Vehicle-position pill. %d is minutes to the user's stop."), minutesAway), systemImage: "bus")
                            .font(.caption2.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(routeColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(routeColor.opacity(0.14), in: Capsule())
                    }
                }
                .frame(minHeight: 30)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
