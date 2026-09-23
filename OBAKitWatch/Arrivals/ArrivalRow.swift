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
            CountdownView(departure: arrival.arrivalDepartureDate, isRealTime: arrival.predicted, color: countdownColor, emphasized: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: OBALoc("arrivals.row.a11y_fmt", value: "%1$@ to %2$@, %3$@", comment: "VoiceOver: route, headsign, time until departure"),
                arrival.routeShortName, headsign, formatters.formattedTime(until: arrival)
            )
        )
    }
}
