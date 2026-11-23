//
//  ArrivalRow.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct ArrivalRow: View {
    let arrival: ArrivalDeparture
    let formatters: Formatters

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var headsign: String {
        arrival.tripHeadsign ?? arrival.routeShortName
    }

    private var routeColor: Color {
        Color(uiColor: arrival.route?.color ?? ThemeColors.shared.brand)
    }

    private var routeTextColor: Color? {
        arrival.route?.textColor.map { Color(uiColor: $0) }
    }

    private var countdownColor: Color {
        Color(uiColor: formatters.colorForScheduleStatus(arrival.scheduleStatus))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RouteBadgeView(routeShortName: arrival.routeShortName, routeColor: routeColor, routeTextColor: routeTextColor, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(headsign)
                    .font(.caption)
                    .lineLimit(2)
                Text(formatters.timeFormatter.string(from: arrival.arrivalDepartureDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // A single-child stack lays out exactly as the bare countdown, so
            // the row is unchanged unless the glyph is drawn.
            HStack(spacing: 2) {
                // Schedule-only countdowns already carry a clock glyph.
                if differentiateWithoutColor, arrival.predicted {
                    Image(systemName: arrival.scheduleStatus.differentiateWithoutColorGlyphName(isRealTime: true))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(countdownColor)
                        .accessibilityHidden(true)
                }
                CountdownView(departure: arrival.arrivalDepartureDate, isRealTime: arrival.predicted, color: countdownColor, emphasized: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: OBALoc("arrivals.row.a11y_fmt", value: "%1$@ to %2$@, %3$@", comment: "VoiceOver: route, headsign, time until departure"),
                arrival.routeShortName, headsign, formatters.formattedTime(until: arrival)
            )
        )
        // The countdown's color is the row's only visual adherence cue unless
        // Differentiate Without Color adds a glyph, and color is inaudible: say it ("2 min late", "Scheduled/not real-time").
        .accessibilityValue(formatters.deviationLabel(for: arrival))
        // A focused row re-speaks as its countdown ticks.
        .accessibilityAddTraits(.updatesFrequently)
    }
}
