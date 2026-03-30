//
//  WalkTimeBanner.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

/// A SwiftUI banner showing walking distance and estimated arrival time at a stop.
///
/// Mirrors the UIKit `WalkTimeView` — hidden when the user is within 40 m of the stop.
/// Supports both the standard walk-time mode and the transfer-arrival mode.
struct WalkTimeBanner: View {

    enum Content {
        case walk(distance: CLLocationDistance, timeToWalk: TimeInterval)
        case transfer(arrivalTime: Date, routeDisplay: String)
    }

    let content: Content
    let formatters: Formatters

    // MARK: - Body

    var body: some View {
        if let row = rowContent {
            HStack(spacing: 8) {
                Text(row.text)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: row.icon)
                    .foregroundStyle(.white)
                    .imageScale(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(ThemeColors.shared.brand))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.a11yLabel)
            .accessibilityValue(row.a11yValue)
        }
    }

    // MARK: - Private helpers

    private struct RowContent {
        let text: String
        let icon: String
        let a11yLabel: String
        let a11yValue: String
    }

    private var rowContent: RowContent? {
        switch content {
        case .walk(let distance, let timeToWalk):
            return walkRowContent(distance: distance, timeToWalk: timeToWalk)
        case .transfer(let arrivalTime, let routeDisplay):
            return transferRowContent(arrivalTime: arrivalTime, routeDisplay: routeDisplay)
        }
    }

    private func walkRowContent(distance: CLLocationDistance, timeToWalk: TimeInterval) -> RowContent? {
        guard distance > 40 else { return nil }

        let distanceString = formatters.distanceFormatter.string(fromDistance: distance)
        let arrivalTime = formatters.timeFormatter.string(from: Date().addingTimeInterval(timeToWalk))

        let displayText: String
        if let timeString = formatters.positionalTimeFormatter.string(from: timeToWalk) {
            let fmt = OBALoc(
                "walk_time_view.distance_time_fmt",
                value: "%@, %@: arriving at %@",
                comment: "Format string for distance, walk time, and arrival time. e.g. 1.2 miles, 17m: arriving at 09:41 A.M."
            )
            displayText = String(format: fmt, distanceString, timeString, arrivalTime)
        } else {
            displayText = distanceString
        }

        let a11yValue: String
        if let timeString = formatters.accessibilityPositionalTimeFormatter.string(from: timeToWalk) {
            let fmt = OBALoc(
                "walk_time_view.accessibility_value",
                value: "%@. Takes %@ to walk, arriving at %@",
                comment: "Accessibility string for distance, walk time, and arrival time."
            )
            a11yValue = String(format: fmt, distanceString, timeString, arrivalTime)
        } else {
            a11yValue = distanceString
        }

        return RowContent(
            text: displayText,
            icon: "figure.walk",
            a11yLabel: OBALoc(
                "walk_time_view.accessibility_label",
                value: "Time to walk to stop",
                comment: "Accessibility label for the walk time banner."
            ),
            a11yValue: a11yValue
        )
    }

    private func transferRowContent(arrivalTime: Date, routeDisplay: String) -> RowContent? {
        let text = formatters.transferArrivalBannerText(arrivalTime: arrivalTime, routeDisplay: routeDisplay)
        return RowContent(
            text: text,
            icon: "arrow.triangle.swap",
            a11yLabel: OBALoc(
                "walk_time_view.transfer_accessibility_label",
                value: "Transfer arrival time",
                comment: "Accessibility label for the transfer arrival banner."
            ),
            a11yValue: text
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Walking — 800 m away") {
    WalkTimeBanner(
        content: .walk(distance: 800, timeToWalk: 600),
        formatters: .init(locale: .current, calendar: .current, themeColors: ThemeColors.shared)
    )
}

#Preview("Walking — too close, hidden") {
    WalkTimeBanner(
        content: .walk(distance: 30, timeToWalk: 20),
        formatters: .init(locale: .current, calendar: .current, themeColors: ThemeColors.shared)
    )
}

#Preview("Transfer arrival") {
    WalkTimeBanner(
        content: .transfer(arrivalTime: Date().addingTimeInterval(300), routeDisplay: "Route 10"),
        formatters: .init(locale: .current, calendar: .current, themeColors: ThemeColors.shared)
    )
}
#endif
