//
//  WidgetMediumView.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-16.
//

import SwiftUI
import WidgetKit
import OBAKitCore

// MARK: - Constants
private enum Constants {
    static let minutes: UInt = 60
    static let maxDeparturesToShow = 3
    static let maxStopDeparturesToShow = 2
    static let rowWidth: CGFloat = 180
    static let fontSize: CGFloat = 13
}

// MARK: - WidgetRowView
struct WidgetRowView: View {
    let bookmark: Bookmark?
    let formatters: Formatters
    let departures: [ArrivalDeparture]?

    private var bookmarkTitle: String {
        bookmark?.name ?? " "
    }

    private var isStopBookmark: Bool {
        bookmark?.isTripBookmark == false
    }

    private var nextDepartureLabel: String {
        if departures != nil {
            return updateNextDepartureLabel()
        } else {
            return LocalizationKeys.tapForMoreInformation
        }
    }

    var body: some View {
        if isStopBookmark {
            stopBookmarkView
        } else {
            tripBookmarkView
        }
    }

    // MARK: - Trip Bookmark Layout (existing)

    private var tripBookmarkView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bookmarkTitle)
                    .font(.system(size: Constants.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(nextDepartureLabel)
                    .font(.system(size: Constants.fontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // if the badge is hidden take up the full width otherwise use constant
            .frame(maxWidth: departures?.isEmpty == false ? Constants.rowWidth : .infinity, alignment: .leading)

            Spacer()

            if departures?.isEmpty == false {
                departureTimeBadges
            }
        }
    }

    // MARK: - Stop Bookmark Layout (next N departures across all routes)

    private var stopBookmarkView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bookmarkTitle)
                .font(.system(size: Constants.fontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            if let departures {
                ForEach(departures.prefix(Constants.maxStopDeparturesToShow), id: \.self) { departure in
                    HStack {
                        Text(departure.routeAndHeadsign)
                            .font(.system(size: Constants.fontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(formatters.shortFormattedTime(until: departure))
                            .font(.system(size: Constants.fontSize, weight: .bold))
                            .foregroundStyle(Color(formatters.backgroundColorForScheduleStatus(departure.scheduleStatus)))
                    }
                }
            }
        }
    }

    // MARK: - Departure Time Badges

    private var departureTimeBadges: some View {
        HStack(spacing: 5) {
            ForEach(departures?.prefix(Constants.maxDeparturesToShow) ?? [], id: \.self) { departure in
                DepartureTimeBadgeView(
                    arrivalDeparture: departure,
                    formatters: formatters
                )
            }
        }
    }

    // MARK: - Helper Functions

    private func updateNextDepartureLabel() -> String {
        guard let departures = departures else {
            return LocalizationKeys.tapForMoreInformation
        }

        if let firstDeparture = departures.first {
            return formatters.formattedScheduleDeviation(for: firstDeparture)
        } else {
            return String(format: LocalizationKeys.noDeparturesInNextNMinutes, String(Constants.minutes))
        }
    }
}

// MARK: - Preview
struct Widget_Previews: PreviewProvider {
    static var previews: some View {
        WidgetRowView(bookmark: nil,
                      formatters: WidgetDataProvider.shared.formatters,
                      departures: [])
        .containerBackground(.ultraThinMaterial.quaternary, for: .widget)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
