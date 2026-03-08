//
//  TripBookmarkRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Shared SwiftUI view for trip bookmarks — used in both the main app (BookmarksViewController)
/// and Live Activities (TripLiveActivity).
public struct TripBookmarkRow: View {
    public let routeShortName: String
    public let routeHeadsign: String
    public let statusText: String
    public let statusColor: Color
    public let minutes: [MinuteDisplay]
    public let isLiveActivity: Bool

    @State private var highlightedBadges: Set<String> = []
    @Environment(\.sizeCategory) private var sizeCategory

    // MARK: - MinuteDisplay

    public struct MinuteDisplay: Identifiable, Equatable {
        /// Stable identifier derived from the minute text content, avoiding index-based IDs
        /// that can cause incorrect SwiftUI diff animations when the array changes.
        public let id: String
        public let text: String
        public let color: Color
        public let isPrimary: Bool
        public let shouldHighlight: Bool

        public init(text: String, color: Color, isPrimary: Bool, shouldHighlight: Bool = false) {
            self.id = "\(isPrimary ? "primary" : "secondary")-\(text)"
            self.text = text
            self.color = color
            self.isPrimary = isPrimary
            self.shouldHighlight = shouldHighlight
        }
    }

    // MARK: - Initialization

    public init(
        routeShortName: String,
        routeHeadsign: String,
        statusText: String,
        statusColor: Color,
        minutes: [MinuteDisplay],
        isLiveActivity: Bool = false
    ) {
        self.routeShortName = routeShortName
        self.routeHeadsign = routeHeadsign
        self.statusText = statusText
        self.statusColor = statusColor
        self.minutes = minutes
        self.isLiveActivity = isLiveActivity
    }

    // MARK: - Shared Status Text Builder

    /// Builds a status string from an `ArrivalDeparture` using the `Formatters`.
    ///
    /// This is for status text, shared between `TripBookmarkCell`
    /// and `BookmarksViewController` (for Live Activity content state).
    ///
    /// - Parameters:
    ///   - arrivalDeparture: The arrival/departure event.
    ///   - formatters: The app's `Formatters` instance.
    /// - Returns: A string like `"3:26 AM - arrives on time"`.
    public static func buildStatusText(from arrivalDeparture: ArrivalDeparture, formatters: Formatters) -> String {
        let timeString = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
        let deviationText: String

        if arrivalDeparture.scheduleStatus == .unknown {
            deviationText = Strings.scheduledNotRealTime
        } else {
            deviationText = formatters.formattedScheduleDeviation(for: arrivalDeparture)
        }

        return "\(timeString) - \(deviationText)"
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if sizeCategory.isAccessibilityCategory {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            guard !isLiveActivity else { return }
            let badgesToHighlight = minutes.filter { $0.shouldHighlight }.map { $0.id }
            guard !badgesToHighlight.isEmpty else { return }

            withAnimation(.easeInOut(duration: 0.3)) {
                highlightedBadges = Set(badgesToHighlight)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    highlightedBadges.removeAll()
                }
            }
        }
    }

    // MARK: - Layouts

    private var regularLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            routeInfoView
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                minutesView
            }
            .frame(minWidth: 48)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            routeInfoView
            HStack(spacing: 8) {
                minutesView
            }
        }
    }

    private var routeInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(routeShortName) - \(routeHeadsign)")
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(sizeCategory.isAccessibilityCategory ? nil : 1)
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
                .lineLimit(1)
        }
    }

    private var minutesView: some View {
        ForEach(minutes) { minute in
            if minute.isPrimary {
                Text(minute.text)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(badgeBackgroundColor(for: minute))
                    )
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            } else {
                Text(minute.text)
                    .font(.subheadline)
                    .foregroundColor(minute.color)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(secondaryBadgeBackgroundColor(for: minute))
                    )
            }
        }
    }

    // MARK: - Badge Highlight Colors

    private func badgeBackgroundColor(for minute: MinuteDisplay) -> Color {
        if !isLiveActivity && minute.shouldHighlight && highlightedBadges.contains(minute.id) {
            return Color(uiColor: ThemeColors.shared.propertyChanged)
        }
        return minute.color
    }

    private func secondaryBadgeBackgroundColor(for minute: MinuteDisplay) -> Color {
        if !isLiveActivity && minute.shouldHighlight && highlightedBadges.contains(minute.id) {
            return Color(uiColor: ThemeColors.shared.propertyChanged)
        }
        return Color.clear
    }
}

// MARK: - Live Activity Convenience Initializer

extension TripBookmarkRow {
    public init(staticData: TripAttributes.StaticData, contentState: TripAttributes.ContentState) {
        let statusColor = Color(contentState.statusColor.uiColor)
        let minuteDisplays = contentState.minutes.enumerated().map { index, minuteInfo in
            MinuteDisplay(
                text: minuteInfo.text,
                color: Color(minuteInfo.color.uiColor),
                isPrimary: index == 0,
                shouldHighlight: contentState.shouldHighlight && index == 0
            )
        }
        self.init(
            routeShortName: staticData.routeShortName,
            routeHeadsign: staticData.routeHeadsign,
            statusText: contentState.statusText,
            statusColor: statusColor,
            minutes: minuteDisplays,
            isLiveActivity: true
        )
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Light Mode - Representative States") {
    VStack(spacing: 0) {
        // On time with all three badges
        TripBookmarkRow(
            routeShortName: "28",
            routeHeadsign: "Carkeek Park",
            statusText: "3:26 AM - arrives on time",
            statusColor: Color(UIColor.systemGreen),
            minutes: [
                .init(text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
                .init(text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
                .init(text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
            ]
        )
        Divider()
        // Late departure
        TripBookmarkRow(
            routeShortName: "578",
            routeHeadsign: "Puyallup",
            statusText: "3:04 AM - arrives 5 min late",
            statusColor: Color(UIColor.systemBlue),
            minutes: [
                .init(text: "6m", color: Color(UIColor.systemBlue), isPrimary: true),
                .init(text: "31m", color: Color(UIColor.systemBlue), isPrimary: false)
            ]
        )
        Divider()
        // Scheduled / no real-time data
        TripBookmarkRow(
            routeShortName: "590",
            routeHeadsign: "Commerce / Tacoma",
            statusText: "2:55 AM - Scheduled/not real-time",
            statusColor: Color(UIColor.systemGray),
            minutes: [
                .init(text: "27m", color: Color(UIColor.systemGray), isPrimary: true)
            ]
        )
        Divider()
        // Loading state (no data)
        TripBookmarkRow(
            routeShortName: "44",
            routeHeadsign: "Ballard",
            statusText: "Loading...",
            statusColor: Color(UIColor.secondaryLabel),
            minutes: []
        )
    }
}

#Preview("Dark Mode") {
    VStack(spacing: 0) {
        TripBookmarkRow(
            routeShortName: "28",
            routeHeadsign: "Carkeek Park",
            statusText: "3:26 AM - arrives on time",
            statusColor: Color(UIColor.systemGreen),
            minutes: [
                .init(text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
                .init(text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
                .init(text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "578",
            routeHeadsign: "Puyallup",
            statusText: "3:04 AM - arrives 5 min late",
            statusColor: Color(UIColor.systemBlue),
            minutes: [
                .init(text: "6m", color: Color(UIColor.systemBlue), isPrimary: true),
                .init(text: "31m", color: Color(UIColor.systemBlue), isPrimary: false)
            ]
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Accessibility XXXLarge") {
    TripBookmarkRow(
        routeShortName: "28",
        routeHeadsign: "Carkeek Park",
        statusText: "3:26 AM - arrives on time",
        statusColor: Color(UIColor.systemGreen),
        minutes: [
            .init(text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
            .init(text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
            .init(text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
        ]
    )
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Highlight Animation") {
    TripBookmarkRow(
        routeShortName: "33",
        routeHeadsign: "E Magnolia",
        statusText: "2:46 AM - arrives 1 min late",
        statusColor: Color(UIColor.systemBlue),
        minutes: [
            .init(text: "5m", color: Color(UIColor.systemBlue), isPrimary: true, shouldHighlight: true),
            .init(text: "15m", color: Color(UIColor.systemBlue), isPrimary: false, shouldHighlight: true),
            .init(text: "34m", color: Color(UIColor.systemBlue), isPrimary: false, shouldHighlight: true)
        ]
    )
}

#endif
