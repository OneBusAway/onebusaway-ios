//
//  ComplicationComponents.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Shared SwiftUI building blocks for Lock Screen accessory complications. Kept
/// WidgetKit-free so `OBAKitCore` stays independent of `WidgetKit`.
@MainActor
public enum ComplicationPresentation {
    /// Live-updating `Text` for a complication countdown: `"NOW"` when under a
    /// minute remains at `referenceDate`, and Apple's narrow minute
    /// `Date.ComponentsFormatStyle` otherwise so out-of-process widgets tick
    /// down automatically (including at low cadence in Always-On mode) without
    /// timeline reloads.
    public static func countdownText(
        for departure: ComplicationDeparture,
        at referenceDate: Date,
        locale: Locale
    ) -> Text {
        if departure.isArrivingNow(at: referenceDate) {
            return Text(verbatim: departure.shortCountdownText(at: referenceDate))
        }
        return Text(.dateRange(endingAt: departure.departureDate), format: TickingCountdownText.visibleFormat(locale: locale))
    }

    /// Sizes the countdown slot using a hidden snapshot so out-of-process
    /// ticking text does not stretch to its format's widest bound or shift
    /// digits off-center.
    @ViewBuilder
    public static func countdownSlot(
        for departure: ComplicationDeparture,
        at referenceDate: Date,
        locale: Locale,
        alignment: Alignment
    ) -> some View {
        let snapshotText = departure.isArrivingNow(at: referenceDate)
            ? departure.shortCountdownText(at: referenceDate)
            : TickingCountdownText.snapshot(departure: departure.departureDate, now: referenceDate, locale: locale)
        Text(verbatim: snapshotText)
            .hidden()
            .overlay(alignment: alignment) {
                countdownText(
                    for: departure,
                    at: referenceDate,
                    locale: locale
                )
                .multilineTextAlignment(alignment == .trailing ? .trailing : (alignment == .leading ? .leading : .center))
                .lineLimit(1)
            }
    }

    /// Concatenated inline `Text` (`"<route> · <countdown> · <headsign>"`) so
    /// route and ticking countdown sit at the leading edge and never truncate
    /// when a headsign is long.
    public static func inlineDepartureText(
        for departure: ComplicationDeparture,
        at referenceDate: Date,
        locale: Locale
    ) -> Text {
        Text(verbatim: "\(departure.routeShortName) · ")
            + countdownText(
                for: departure,
                at: referenceDate,
                locale: locale
            )
            + Text(verbatim: " · \(departure.headsign)")
    }

    /// Snapshot equivalent of `inlineDepartureText`, used to verify the
    /// route/countdown/headsign content without trying to introspect SwiftUI's
    /// opaque `Text` value in tests.
    static func inlineDepartureSnapshot(
        for departure: ComplicationDeparture,
        at referenceDate: Date,
        locale: Locale
    ) -> String {
        let countdown = departure.isArrivingNow(at: referenceDate)
            ? departure.shortCountdownText(at: referenceDate)
            : TickingCountdownText.snapshot(
                departure: departure.departureDate,
                now: referenceDate,
                locale: locale
            )
        return "\(departure.routeShortName) · \(countdown) · \(departure.headsign)"
    }

    /// Foreground color for status/countdown text: schedule-status tint in full
    /// color mode, `.primary` in accented/vibrant complication rendering.
    public static func statusForegroundColor(
        for scheduleStatus: ScheduleStatus,
        formatters: Formatters,
        isFullColor: Bool
    ) -> Color {
        guard isFullColor else { return .primary }
        return Color(uiColor: formatters.colorForScheduleStatus(scheduleStatus))
    }

    /// Combined VoiceOver label pairing route, headsign, ticking spoken countdown, clock time, and stop name.
    public static func departureAccessibilityLabel(
        for departure: ComplicationDeparture,
        formatters: Formatters,
        isLuminanceReduced: Bool,
        locale: Locale
    ) -> Text {
        let routeLabel = formatters.accessibilityLabelForArrivalDeparture(
            routeAndHeadsign: "\(departure.routeShortName) \(departure.headsign)"
        )
        let countdown = TickingCountdownText.spokenText(
            departure: departure.departureDate,
            isLuminanceReduced: isLuminanceReduced,
            locale: locale
        )
        let clockTime = formatters.timeFormatter.string(from: departure.departureDate)
        return Text(verbatim: "\(routeLabel), ")
            + countdown
            + Text(verbatim: ", \(clockTime), \(departure.stopName)")
    }

    /// Snapshot equivalent of `departureAccessibilityLabel`, used to verify
    /// its localized route, headsign, countdown, clock time, and stop content.
    static func departureAccessibilitySnapshot(
        for departure: ComplicationDeparture,
        formatters: Formatters,
        at referenceDate: Date,
        locale: Locale
    ) -> String {
        let routeLabel = formatters.accessibilityLabelForArrivalDeparture(
            routeAndHeadsign: "\(departure.routeShortName) \(departure.headsign)"
        )
        let countdown = TickingCountdownText.spokenSnapshot(
            departure: departure.departureDate,
            now: referenceDate,
            locale: locale
        )
        let clockTime = formatters.timeFormatter.string(from: departure.departureDate)
        return "\(routeLabel), \(countdown), \(clockTime), \(departure.stopName)"
    }
}

/// Compact route badge that adapts to full-color vs. accented/vibrant widget rendering.
public struct ComplicationRouteBadge: View {
    public let routeShortName: String
    public let routeColorHex: String?
    public let routeTextColorHex: String?
    public let isFullColor: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        routeShortName: String,
        routeColorHex: String?,
        routeTextColorHex: String?,
        isFullColor: Bool
    ) {
        self.routeShortName = routeShortName
        self.routeColorHex = routeColorHex
        self.routeTextColorHex = routeTextColorHex
        self.isFullColor = isFullColor
    }

    public var body: some View {
        let label = Text(verbatim: routeShortName)
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)

        if isFullColor {
            let routeUIColor = routeColorHex.flatMap { UIColor(hex: $0) } ?? ThemeColors.shared.brand
            let preferredTextUIColor = routeTextColorHex.flatMap { UIColor(hex: $0) }
            let routeColor = Color(uiColor: routeUIColor)
            let textColor = RouteBadgeStyle.textColor(
                routeColor: routeColor,
                routeTextColor: preferredTextUIColor.map { Color(uiColor: $0) },
                contrast: contrast
            )
            label
                .foregroundStyle(textColor)
                .background(routeColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            label
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.primary.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

/// Shared circular departure layout (route short name over ticking countdown).
public struct ComplicationCircularDepartureContent: View {
    public let departure: ComplicationDeparture
    public let referenceDate: Date
    public let formatters: Formatters
    public let isFullColor: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.locale) private var locale

    public init(
        departure: ComplicationDeparture,
        referenceDate: Date,
        formatters: Formatters,
        isFullColor: Bool
    ) {
        self.departure = departure
        self.referenceDate = referenceDate
        self.formatters = formatters
        self.isFullColor = isFullColor
    }

    public var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: departure.routeShortName)
                .font(.system(.caption2, design: .rounded, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ComplicationPresentation.countdownSlot(
                for: departure,
                at: referenceDate,
                locale: locale,
                alignment: .center
            )
            .font(.system(.title3, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(ComplicationPresentation.statusForegroundColor(
                for: departure.scheduleStatus,
                formatters: formatters,
                isFullColor: isFullColor
            ))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ComplicationPresentation.departureAccessibilityLabel(
            for: departure,
            formatters: formatters,
            isLuminanceReduced: isLuminanceReduced,
            locale: locale
        ))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shared rectangular departure layout (route badge + real-time/scheduled countdown, headsign, clock time + stop).
public struct ComplicationRectangularDepartureContent: View {
    public let departure: ComplicationDeparture
    public let referenceDate: Date
    public let formatters: Formatters
    public let isFullColor: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.locale) private var locale

    public init(
        departure: ComplicationDeparture,
        referenceDate: Date,
        formatters: Formatters,
        isFullColor: Bool
    ) {
        self.departure = departure
        self.referenceDate = referenceDate
        self.formatters = formatters
        self.isFullColor = isFullColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ComplicationRouteBadge(
                    routeShortName: departure.routeShortName,
                    routeColorHex: departure.routeColorHex,
                    routeTextColorHex: departure.routeTextColorHex,
                    isFullColor: isFullColor
                )

                Spacer(minLength: 4)

                HStack(spacing: 2) {
                    Image(systemName: departure.isRealTime ? "dot.radiowaves.up.forward" : "clock")
                        .font(.caption2.weight(.semibold))
                    ComplicationPresentation.countdownSlot(
                        for: departure,
                        at: referenceDate,
                        locale: locale,
                        alignment: .trailing
                    )
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .monospacedDigit()
                }
                .foregroundStyle(ComplicationPresentation.statusForegroundColor(
                    for: departure.scheduleStatus,
                    formatters: formatters,
                    isFullColor: isFullColor
                ))
            }
            Text(verbatim: departure.headsign)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(verbatim: "\(formatters.timeFormatter.string(from: departure.departureDate)) · \(departure.stopName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ComplicationPresentation.departureAccessibilityLabel(
            for: departure,
            formatters: formatters,
            isLuminanceReduced: isLuminanceReduced,
            locale: locale
        ))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Fallback body for circular complications when no departure is shown.
public struct ComplicationCircularFallbackContent: View {
    public let routeShortName: String?
    public let systemImage: String
    public let accessibilityText: String

    public init(routeShortName: String?, systemImage: String, accessibilityText: String) {
        self.routeShortName = routeShortName
        self.systemImage = systemImage
        self.accessibilityText = accessibilityText
    }

    public var body: some View {
        VStack(spacing: 1) {
            if let routeShortName, !routeShortName.isEmpty {
                Text(verbatim: routeShortName)
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                    Text(verbatim: "--")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(verbatim: "--")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Fallback body for rectangular complications when no departure is shown.
public struct ComplicationRectangularFallbackContent: View {
    public let title: String
    public let subtitle: String
    public let systemImage: String?

    public init(title: String, subtitle: String, systemImage: String?) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Text(verbatim: subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
