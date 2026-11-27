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

    let displayText: String
    let accessibilityLabel: String
    let scheduleStatus: ScheduleStatus
    let formatters: Formatters

    init(arrivalDeparture: ArrivalDeparture, formatters: Formatters, now: Date = Date()) {
        self.init(
            displayText: formatters.shortFormattedTime(until: arrivalDeparture, now: now),
            accessibilityLabel: formatters.explanation(from: arrivalDeparture, now: now),
            scheduleStatus: arrivalDeparture.scheduleStatus,
            formatters: formatters
        )
    }

    /// For a badge that isn't an `ArrivalDeparture`, such as an offline timetable time.
    init(displayText: String, accessibilityLabel: String, scheduleStatus: ScheduleStatus, formatters: Formatters) {
        self.displayText = displayText
        self.accessibilityLabel = accessibilityLabel
        self.scheduleStatus = scheduleStatus
        self.formatters = formatters
    }

    private var fillColor: UIColor {
        formatters.backgroundColorForScheduleStatus(scheduleStatus)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Dark text on light fills (the gray of a scheduled-only departure),
    /// opaque white on the rest. Not `contrastingTextColor`: its light choice
    /// is `UIColor.lightText`, which is white at 60% opacity.
    ///
    /// The fill is resolved against this view's environment first: `isLightColor`
    /// reads `getRed`, which otherwise resolves a dynamic color against
    /// `UITraitCollection.current`, not the appearance the widget renders in.
    private var textColor: UIColor {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let contrast: UIAccessibilityContrast = colorSchemeContrast == .increased ? .high : .normal
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.accessibilityContrast = contrast
        }
        return fillColor.resolvedColor(with: traits).isLightColor ? .darkText : ThemeColors.shared.lightText
    }

    var body: some View {
        VStack {
            Text("\(displayText)")
                .badgeStyle(
                    backgroundColor: Color(fillColor),
                    textColor: Color(textColor),
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
