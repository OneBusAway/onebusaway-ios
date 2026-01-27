//
//  TripBookmarkRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

// Shared view for trip bookmarks - used in both main app (BookmarkViewController) and Live Activities
public struct TripBookmarkRow: View {
    public let routeShortName: String
    public let routeHeadsign: String
    public let statusText: String
    public let statusColor: Color
    public let minutes: [MinuteDisplay]
    public let isLiveActivity: Bool
    @State private var highlightedBadges: Set<Int> = []
    @Environment(\.sizeCategory) private var sizeCategory
    public struct MinuteDisplay: Identifiable, Equatable {
        public let id: Int
        public let text: String
        public let color: Color
        public let isPrimary: Bool
        public let shouldHighlight: Bool
        public init(id: Int, text: String, color: Color, isPrimary: Bool, shouldHighlight: Bool = false) {
            self.id = id
            self.text = text
            self.color = color
            self.isPrimary = isPrimary
            self.shouldHighlight = shouldHighlight
        }
    }
    public init(routeShortName: String, routeHeadsign: String, statusText: String, statusColor: Color, minutes: [MinuteDisplay], isLiveActivity: Bool = false) {
        self.routeShortName = routeShortName
        self.routeHeadsign = routeHeadsign
        self.statusText = statusText
        self.statusColor = statusColor
        self.minutes = minutes
        self.isLiveActivity = isLiveActivity
    }
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

extension TripBookmarkRow {
    public init(staticData: TripAttributes.StaticData, contentState: TripAttributes.ContentState) {
        let statusColor = Color(contentState.statusColor.uiColor)
        let minuteDisplays = contentState.minutes.enumerated().map { index, minuteInfo in
            MinuteDisplay(
                id: index,
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

extension ContentSizeCategory {
    var isAccessibilityCategory: Bool {
        switch self {
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge:
            return true
        default:
            return false
        }
    }
}

// canvas preview for ui
#if DEBUG
import SwiftUI

#Preview("Light Mode - All States") {
    VStack(spacing: 0) {
        TripBookmarkRow(
            routeShortName: "28",
            routeHeadsign: "Carkeek Park",
            statusText: "3:26 AM - arrives on time",
            statusColor: Color(UIColor.systemGreen),
            minutes: [
                .init(id: 0, text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
                .init(id: 1, text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
                .init(id: 2, text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "578",
            routeHeadsign: "Puyallup",
            statusText: "3:04 AM - arrives 5 min late",
            statusColor: Color(UIColor.systemBlue),
            minutes: [
                .init(id: 0, text: "6m", color: Color(UIColor.systemBlue), isPrimary: true),
                .init(id: 1, text: "31m", color: Color(UIColor.systemBlue), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "33",
            routeHeadsign: "E Magnolia",
            statusText: "2:46 AM - arrives 3 min early",
            statusColor: Color(UIColor.systemRed),
            minutes: [
                .init(id: 0, text: "16m", color: Color(UIColor.systemRed), isPrimary: true),
                .init(id: 1, text: "45m", color: Color(UIColor.systemRed), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "590",
            routeHeadsign: "Commerce / Tacoma",
            statusText: "2:55 AM - Scheduled/not real-time",
            statusColor: Color(UIColor.systemGray),
            minutes: [
                .init(id: 0, text: "27m", color: Color(UIColor.systemGray), isPrimary: true),
                .init(id: 1, text: "57m", color: Color(UIColor.systemGray), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "44",
            routeHeadsign: "Ballard",
            statusText: "Loading...",
            statusColor: Color(UIColor.secondaryLabel),
            minutes: []
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "C",
            routeHeadsign: "West Seattle Alaska Junction",
            statusText: "Departing now",
            statusColor: Color(UIColor.systemGreen),
            minutes: [
                .init(id: 0, text: "NOW", color: Color(UIColor.systemGreen), isPrimary: true),
                .init(id: 1, text: "8m", color: Color(UIColor.systemGreen), isPrimary: false),
                .init(id: 2, text: "18m", color: Color(UIColor.systemGreen), isPrimary: false)
            ]
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
                .init(id: 0, text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
                .init(id: 1, text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
                .init(id: 2, text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "578",
            routeHeadsign: "Puyallup",
            statusText: "3:04 AM - arrives 5 min late",
            statusColor: Color(UIColor.systemBlue),
            minutes: [
                .init(id: 0, text: "6m", color: Color(UIColor.systemBlue), isPrimary: true),
                .init(id: 1, text: "31m", color: Color(UIColor.systemBlue), isPrimary: false)
            ]
        )
        Divider()
        TripBookmarkRow(
            routeShortName: "590",
            routeHeadsign: "Commerce / Tacoma",
            statusText: "2:55 AM - Scheduled/not real-time",
            statusColor: Color(UIColor.systemGray),
            minutes: [
                .init(id: 0, text: "27m", color: Color(UIColor.systemGray), isPrimary: true),
                .init(id: 1, text: "57m", color: Color(UIColor.systemGray), isPrimary: false)
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
            .init(id: 0, text: "5m", color: Color(UIColor.systemGreen), isPrimary: true),
            .init(id: 1, text: "15m", color: Color(UIColor.systemGreen), isPrimary: false),
            .init(id: 2, text: "25m", color: Color(UIColor.systemGreen), isPrimary: false)
        ]
    )
    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}

#Preview("Highlight Animation - All Badges") {
    TripBookmarkRow(
        routeShortName: "33",
        routeHeadsign: "E Magnolia",
        statusText: "2:46 AM - arrives 1 min late",
        statusColor: Color(UIColor.systemBlue),
        minutes: [
            .init(id: 0, text: "5m", color: Color(UIColor.systemBlue), isPrimary: true, shouldHighlight: true),
            .init(id: 1, text: "15m", color: Color(UIColor.systemBlue), isPrimary: false, shouldHighlight: true),
            .init(id: 2, text: "34m", color: Color(UIColor.systemBlue), isPrimary: false, shouldHighlight: true)
        ]
    )
}

#Preview("Highlight Animation - Primary Only") {
    TripBookmarkRow(
        routeShortName: "C",
        routeHeadsign: "West Seattle Alaska Junction",
        statusText: "Departing now",
        statusColor: Color(UIColor.systemGreen),
        minutes: [
            .init(id: 0, text: "NOW", color: Color(UIColor.systemGreen), isPrimary: true, shouldHighlight: true),
            .init(id: 1, text: "8m", color: Color(UIColor.systemGreen), isPrimary: false),
            .init(id: 2, text: "18m", color: Color(UIColor.systemGreen), isPrimary: false)
        ]
    )
 }

#Preview("Long Route Names") {
    TripBookmarkRow(
        routeShortName: "999",
        routeHeadsign: "Very Long Destination Name That Should Truncate Properly",
        statusText: "3:26 AM - arrives on time",
        statusColor: Color(UIColor.systemGreen),
        minutes: [
            .init(id: 0, text: "999m", color: Color(UIColor.systemGreen), isPrimary: true)
        ]
    )
 }

#Preview("Single Badge") {
    TripBookmarkRow(
        routeShortName: "7",
        routeHeadsign: "Rainier Beach",
        statusText: "Departing now",
        statusColor: Color(UIColor.systemGreen),
        minutes: [
            .init(id: 0, text: "NOW", color: Color(UIColor.systemGreen), isPrimary: true)
        ]
    )
}
#endif
