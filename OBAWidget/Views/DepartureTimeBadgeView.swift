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
        VStack {
            Text("\(displayText)")
                .badgeStyle(
                    backgroundColor: backgroundColor,
                    textColor: foregroundColor,
                    accessibilityLabel: accessibilityLabel
                )
        }

    }
}

extension View {
    func badgeStyle(backgroundColor: Color, textColor: Color, accessibilityLabel: String) -> some View {
        self.modifier(BadgeStyle(backgroundColor: backgroundColor, textColor: textColor, accessibilityLabel: accessibilityLabel))
    }
}

struct BadgeStyle: ViewModifier {
    let backgroundColor: Color
    let textColor: Color
    let accessibilityLabel: String

    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    private var rendersFullColor: Bool {
        widgetRenderingMode == .fullColor
    }

    func body(content: Content) -> some View {
        let base = content
            .font(.system(size: 13))
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
            .frame(width: 40, height: 25)
            .accessibilityLabel(accessibilityLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

        if rendersFullColor {
            base
                .foregroundStyle(textColor)
                .background(backgroundColor)
                .cornerRadius(8)
        } else {
            base
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary.opacity(0.35), lineWidth: 1)
                )
        }
    }
}
