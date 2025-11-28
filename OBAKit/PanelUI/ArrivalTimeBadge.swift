//
//  ArrivalTimeBadge.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A badge displaying a single arrival/departure time with colored background based on schedule status
struct ArrivalTimeBadge: View {
    let arrivalDeparture: ArrivalDeparture
    let formatters: Formatters

    private var displayText: String {
        formatters.shortFormattedTime(
            untilMinutes: arrivalDeparture.arrivalDepartureMinutes,
            temporalState: arrivalDeparture.temporalState
        )
    }

    private var accessibilityLabel: String {
        formatters.explanationForArrivalDeparture(
            tempuraState: arrivalDeparture.temporalState,
            arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
            arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes
        )
    }

    private var scheduleColor: UIColor {
        formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus)
    }

    private var backgroundColor: Color {
        Color(scheduleColor)
    }

    private var foregroundColor: Color {
        Color(scheduleColor.contrastingTextColor)
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(accessibilityLabel)
    }
}

/// A container view displaying up to 3 arrival time badges horizontally
struct ArrivalBadgesView: View {
    let arrivals: [ArrivalDeparture]
    let formatters: Formatters

    var body: some View {
        HStack(spacing: 4) {
            ForEach(arrivals.prefix(3), id: \.tripID) { arrival in
                ArrivalTimeBadge(arrivalDeparture: arrival, formatters: formatters)
            }
        }
    }
}
