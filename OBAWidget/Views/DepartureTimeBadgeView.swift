//
//  DepartureTimeBadgeView.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-14.
//

import SwiftUI
import WidgetKit
import OBAKitCore

struct DepartureTimeBadgeView: View {

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

    private var backgroundColor: Color {
        Color(formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus))

    }

    var body: some View {
        VStack {
            Text("\(displayText)")
                .badgeStyle(
                    backgroundColor: backgroundColor,
                    accessibilityLabel: accessibilityLabel
                )
        }

    }
}

extension View {
    func badgeStyle(backgroundColor: Color, accessibilityLabel: String) -> some View {
        self.modifier(BadgeStyle(backgroundColor: backgroundColor, accessibilityLabel: accessibilityLabel))
    }
}

struct BadgeStyle: ViewModifier {
    let backgroundColor: Color
    let accessibilityLabel: String
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
            .frame(width: 40, height: 25)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .accessibilityLabel(accessibilityLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
