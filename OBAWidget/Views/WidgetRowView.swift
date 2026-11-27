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
    static let minutes = 60
    static let maxDeparturesToShow = 3
    static let maxStopDeparturesToShow = 2
    static let rowWidth: CGFloat = 180
}

// MARK: - WidgetRowView
struct WidgetRowView: View {
    let bookmark: Bookmark?
    let formatters: Formatters
    let departures: [ArrivalDeparture]?

    /// Offline only, `nil` while live: the saved timetable's upcoming
    /// departures, shown once the saved real-time ones have all left.
    var scheduledDepartures: [ScheduledDeparture]?

    /// The timeline entry date this row is rendered for. Countdowns and
    /// accessibility strings are computed relative to `entryDate` rather than
    /// `Date.now` so future archived timeline entries reflect the time when
    /// WidgetKit displays them (#1993).
    var entryDate: Date = .now

    /// The stop rows' countdown tint is otherwise their only adherence cue.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var bookmarkTitle: String {
        bookmark?.name ?? " "
    }

    /// Fallback copy for the second line when there is no departure to
    /// describe: no data yet → "tap for more information"; fetched-but-empty →
    /// "no departures in the next hour". Only reached when `departures?.first`
    /// is nil, so the two cases below are exhaustive.
    ///
    /// Offline, saved data can't say nothing is coming, so it reads as no data.
    private var fallbackLabel: String {
        guard departures != nil, scheduledDepartures == nil else { return LocalizationKeys.tapForMoreInformation }

        return WidgetStrings.noDepartures(inNextMinutes: Constants.minutes)
    }

    /// The timetable departures to show: none while a real-time one is left.
    private var timetable: [ScheduledDeparture] {
        departures?.isEmpty == false ? [] : (scheduledDepartures ?? [])
    }

    var body: some View {
        if bookmark?.isTripBookmark == true {
            tripBookmarkView
        } else {
            stopBookmarkView
        }
    }

    private var titleText: some View {
        Text(bookmarkTitle)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Trip Bookmark Layout

    private var tripBookmarkView: some View {
        HStack {
            VStack(alignment: .leading) {
                titleText

                departureLabel
            }
            // if the badge is hidden take up the full width otherwise use constant
            .frame(maxWidth: departures?.isEmpty == false || !timetable.isEmpty ? Constants.rowWidth : .infinity, alignment: .leading)

            Spacer()

            if departures?.isEmpty == false {
                departureTimeBadges
            } else if !timetable.isEmpty {
                timetableBadges
            }
        }
    }

    // MARK: - Stop Bookmark Layout (next N departures across all routes)

    private var stopBookmarkView: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleText

            if let departures, !departures.isEmpty {
                ForEach(departures.prefix(Constants.maxStopDeparturesToShow), id: \.self) { departure in
                    HStack {
                        Text(departure.routeAndHeadsign)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        // A single-child stack lays out exactly as the bare text,
                        // so the row is unchanged unless the glyph is drawn.
                        HStack(spacing: 2) {
                            if differentiateWithoutColor {
                                // Decorative: the row's label already speaks the status.
                                Image(systemName: departure.scheduleStatus.differentiateWithoutColorGlyphName(isRealTime: departure.predicted))
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                            }
                            Text(formatters.shortFormattedTime(until: departure, now: entryDate))
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color(formatters.colorForScheduleStatus(departure.scheduleStatus)))
                    }
                    .accessibilityElement(children: .ignore)
                    // The countdown's tint is inaudible: say the adherence too.
                    .accessibilityLabel("\(departure.routeAndHeadsign), \(formatters.explanation(from: departure, now: entryDate)), \(formatters.deviationLabel(for: departure, now: entryDate))")
                }
            } else if !timetable.isEmpty {
                ForEach(timetable.prefix(Constants.maxStopDeparturesToShow), id: \.self) { departure in
                    HStack {
                        Text(Self.routeAndHeadsign(departure))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(Self.shortTime(departure, formatters: formatters, now: entryDate))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color(formatters.colorForScheduleStatus(.unknown)))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Self.routeAndHeadsign(departure)), \(Self.explanation(departure, formatters: formatters, now: entryDate)), \(Strings.scheduledNotRealTime)")
                }
            } else {
                Text(fallbackLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
            let deviation = formatters.deviationLabel(for: first, now: entryDate)

            (DepartureTimeText.text(for: display)
                + Text(" · ").foregroundStyle(.tertiary)
                + Text(deviation))
                .font(.footnote)
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
        } else if let first = timetable.first {
            (Text(formatters.timeFormatter.string(from: first.date))
                + Text(" · ").foregroundStyle(.tertiary)
                + Text(Strings.scheduledNotRealTime))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            Text(fallbackLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Timetable Departures

    /// A timetable row reads like a live one: "75 - Northgate".
    private static func routeAndHeadsign(_ departure: ScheduledDeparture) -> String {
        [departure.route?.shortName, departure.tripHeadsign]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    private static func temporalState(forMinutes minutes: Int) -> TemporalState {
        if minutes < 0 {
            return .past
        } else if minutes == 0 {
            return .present
        } else {
            return .future
        }
    }

    static func shortTime(_ departure: ScheduledDeparture, formatters: Formatters, now: Date = .now) -> String {
        let minutes = departure.minutes(from: now)
        return formatters.shortFormattedTime(untilMinutes: minutes, temporalState: temporalState(forMinutes: minutes))
    }

    static func explanation(_ departure: ScheduledDeparture, formatters: Formatters, now: Date = .now) -> String {
        let minutes = departure.minutes(from: now)
        return formatters.explanationForArrivalDeparture(
            tempuraState: temporalState(forMinutes: minutes),
            arrivalDepartureStatus: .departing,
            arrivalDepartureMinutes: minutes
        )
    }

    /// Gray, like a live departure with no real-time data: nothing tracks a
    /// timetable time.
    private var timetableBadges: some View {
        HStack(spacing: 5) {
            ForEach(timetable.prefix(Constants.maxDeparturesToShow), id: \.self) { departure in
                DepartureTimeBadgeView(
                    displayText: Self.shortTime(departure, formatters: formatters, now: entryDate),
                    accessibilityLabel: Self.explanation(departure, formatters: formatters, now: entryDate),
                    scheduleStatus: .unknown,
                    formatters: formatters
                )
            }
        }
    }

    // MARK: - Departure Time Badges

    private var departureTimeBadges: some View {
        HStack(spacing: 5) {
            ForEach(departures?.prefix(Constants.maxDeparturesToShow) ?? [], id: \.self) { departure in
                DepartureTimeBadgeView(
                    arrivalDeparture: departure,
                    formatters: formatters,
                    now: entryDate
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
