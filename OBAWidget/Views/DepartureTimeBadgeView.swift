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

    /// The schedule-status color, except that on-time badges use
    /// `departureOnTimeFill`: in dark mode the on-time color is systemGreen,
    /// which white text only reaches 2.0:1 against.
    private var fillColor: UIColor {
        if arrivalDeparture.scheduleStatus == .onTime {
            return ThemeColors.shared.departureOnTimeFill
        }
        return formatters.backgroundColorForScheduleStatus(arrivalDeparture.scheduleStatus)
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
