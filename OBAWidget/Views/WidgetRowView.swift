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

    /// Fallback copy for the second line when there is no departure to
    /// describe: no data yet → "tap for more information"; fetched-but-empty →
    /// "no departures in the next hour". Only reached when `departures?.first`
    /// is nil, so the two cases below are exhaustive.
    private var fallbackLabel: String {
        guard departures != nil else { return LocalizationKeys.tapForMoreInformation }

        return String(format: LocalizationKeys.noDeparturesInNextNMinutes, String(Constants.minutes))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bookmarkTitle)
                    .font(.system(size: Constants.fontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                departureLabel
            }
            // if the badge is hidden take up the full width otherwise use constant
            .frame(maxWidth: departures?.isEmpty == false ? Constants.rowWidth : .infinity, alignment: .leading)

            Spacer()

            if departures?.isEmpty == false {
                departureTimeBadges
            }
        }
    }

    /// The second line: the corrected clock time and the schedule status —
    /// the deviation phrase, or "Scheduled/not real-time" for schedule-only
    /// trips — in the "time · status" idiom the stop page and bookmark cards
    /// use, or `fallbackLabel` when there is no departure to describe. When a
    /// prediction moves the trip off its timetable, the scheduled time renders
    /// struck through ahead of the corrected one (#1225).
    ///
    /// Built as one concatenated `Text`, not an `HStack`: the struck-through
    /// case can outgrow the fixed text column, and a single text run wraps to
    /// the second line the way this label always has, where an `HStack` would
    /// truncate the deviation — precisely the correction the line exists to
    /// show.
    @ViewBuilder
    private var departureLabel: some View {
        if let first = departures?.first {
            // `deviationLabel`, not `formattedScheduleDeviation`: a schedule-only
            // trip has zero deviation by definition, and pairing "departs on
            // time" with a concrete clock time reads as a real-time claim the
            // data can't back. Schedule-only trips say "Scheduled/not real-time".
            let display = DepartureTimeDisplay(arrivalDeparture: first, formatters: formatters)
            let deviation = formatters.deviationLabel(for: first)

            (DepartureTimeText.text(for: display)
                + Text(" · ").foregroundStyle(.tertiary)
                + Text(deviation))
                .font(.system(size: Constants.fontSize))
                .foregroundStyle(.secondary)
                // No `fixedSize`: the label wraps to its two lines whenever the
                // row has room, but under `.systemLarge` height pressure (seven
                // rows, several of them wrapping) it compresses to a truncated
                // line instead of forcing its full height and pushing whole
                // rows off the bottom of the widget canvas.
                .lineLimit(2)
                // The strikethrough is inaudible, so speak the correction in
                // words instead of letting VoiceOver read two bare times.
                .accessibilityLabel("\(display.accessibilityTimeDescription), \(deviation)")
        } else {
            Text(fallbackLabel)
                .font(.system(size: Constants.fontSize))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
