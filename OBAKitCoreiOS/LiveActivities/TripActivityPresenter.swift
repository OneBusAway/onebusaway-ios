//
//  TripActivityPresenter.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit

/// Derives presentation (minute chips, colors, status line) from the semantic
/// Live Activity `ContentState`. Both the widget extension and the in-app
/// bookmark row use this, so pushed updates and local refreshes render
/// identically. Presentation lives on-device — the server never sends
/// localized strings or colors.
public struct TripActivityPresenter {
    private let formatters: Formatters

    public init(formatters: Formatters = Formatters(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent, themeColors: ThemeColors.shared)) {
        self.formatters = formatters
    }

    public func minuteText(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date = Date()) -> String {
        let minutes = Int(arrival.departureDate.timeIntervalSince(now) / 60.0)
        return formatters.shortFormattedTime(untilMinutes: minutes, temporalState: temporalState(minutes: minutes))
    }

    public func color(for arrival: TripAttributes.ContentState.ArrivalInfo) -> UIColor {
        formatters.colorForScheduleStatus(arrival.scheduleStatus.scheduleStatus)
    }

    /// e.g. "3:26 PM - arrives on time" / "3:26 PM - Scheduled/not real-time".
    public func statusText(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date = Date()) -> String {
        // Unbadged on purpose, and the least obvious of the calls audited for #1438:
        // this clock does stand alone on a Lock Screen. It stays bare because a
        // Live Activity tracks a trip the rider is currently taking, so they are in
        // the region whose zone this is, and the card has no room to spare. Revisit
        // if Track ever survives leaving the region.
        let timeString = formatters.timeFormatter.string(from: arrival.departureDate)

        let deviationText: String
        if arrival.scheduleStatus == .unknown {
            deviationText = Strings.scheduledNotRealTime
        } else {
            let minutes = Int(arrival.departureDate.timeIntervalSince(now) / 60.0)
            deviationText = formatters.formattedScheduleDeviation(
                temporalState: temporalState(minutes: minutes),
                arrivalDepartureStatus: arrival.isArrival ? .arriving : .departing,
                scheduleDeviation: Int((Double(arrival.scheduleDeviation) / 60.0).rounded())
            )
        }

        return "\(timeString) - \(deviationText)"
    }

    /// Just the adherence deviation text, e.g. "arrives on time" or "2 min late".
    /// Used by card-header layouts that display the scheduled time separately.
    public func deviationLabel(for arrival: TripAttributes.ContentState.ArrivalInfo, now: Date = Date()) -> String {
        if arrival.scheduleStatus == .unknown {
            return Strings.scheduledNotRealTime
        }
        let minutes = Int(arrival.departureDate.timeIntervalSince(now) / 60.0)
        return formatters.formattedScheduleDeviation(
            temporalState: temporalState(minutes: minutes),
            arrivalDepartureStatus: arrival.isArrival ? .arriving : .departing,
            scheduleDeviation: Int((Double(arrival.scheduleDeviation) / 60.0).rounded())
        )
    }

    /// The corrected clock time(s) for an arrival: the scheduled time (struck
    /// through by `DepartureTimeText`) ahead of the predicted one when the two
    /// render differently.
    ///
    /// `ContentState` doesn't carry the scheduled instant, so it's derived by
    /// walking `scheduleDeviation` back off the departure time. App-built
    /// content states round the deviation to whole minutes
    /// (`deviationFromScheduleInMinutes * 60`), so for locally-started
    /// activities the derived time can sit up to half a minute off the true
    /// timetable — occasionally shifting the struck-through minute by one.
    /// Server pushes carry raw seconds, where the derivation is exact.
    /// Carrying the exact scheduled time instead would be a change to the
    /// OBACloud content-state wire contract, which isn't worth it for a
    /// glanceable correction affordance.
    public func timeDisplay(for arrival: TripAttributes.ContentState.ArrivalInfo) -> DepartureTimeDisplay {
        // `.unknown` means the feed offered no prediction, so `departureDate`
        // *is* the timetable time. A deviation riding along anyway is data the
        // feed told us not to trust — walking it back here would shift the
        // displayed schedule by exactly that untrusted amount.
        let isRealTime = arrival.scheduleStatus != .unknown
        let scheduledDate = isRealTime
            ? arrival.departureDate.addingTimeInterval(-TimeInterval(arrival.scheduleDeviation))
            : arrival.departureDate

        return DepartureTimeDisplay(
            scheduledDate: scheduledDate,
            expectedDate: arrival.departureDate,
            isRealTime: isRealTime,
            formatters: formatters
        )
    }

    /// Color for the first upcoming arrival; gray when all have departed or empty.
    public func primaryColor(for state: TripAttributes.ContentState, now: Date = Date()) -> UIColor {
        guard let first = state.upcomingArrivals(now: now).first else {
            return formatters.colorForScheduleStatus(.unknown)
        }
        return color(for: first)
    }

    // MARK: - Accessibility

    /// One piece of the card's spoken label. Countdowns stay symbolic so the
    /// view can render them as ticking `Text` — a label baked to a string at
    /// render time would keep saying "8 minutes" until the next push.
    public enum SpokenSegment: Equatable {
        case text(String)
        case countdown(Date)
    }

    /// The Live Activity card's VoiceOver label, in reading order: route,
    /// headsign, the primary countdown, its clock time and adherence, then the
    /// later departures and, last, the stale warning.
    ///
    /// The card is one element on purpose. Read child by child it was "8",
    /// "Downtown", "3:26 PM, on time", "8m", "15m" — the minutes abbreviated so
    /// VoiceOver said "meters", and nothing tying the route to its countdown.
    public func accessibilitySegments(
        staticData: TripAttributes.StaticData,
        contentState: TripAttributes.ContentState,
        isStale: Bool,
        now: Date = Date()
    ) -> [SpokenSegment] {
        let upcoming = contentState.upcomingArrivals(now: now)
        var segments: [SpokenSegment] = [
            .text(formatters.accessibilityLabelForArrivalDeparture(routeAndHeadsign: staticData.routeShortName)),
            .text(staticData.routeHeadsign)
        ]

        if let primary = upcoming.first {
            segments.append(.countdown(primary.departureDate))
            segments.append(.text(timeDisplay(for: primary).accessibilityTimeDescription))
            segments.append(.text(deviationLabel(for: primary, now: now)))
        }

        let later = upcoming.dropFirst()
        if !later.isEmpty {
            segments.append(.text(OBALoc("live_activity.a11y_later_departures", value: "later departures", comment: "VoiceOver lead-in before the spoken list of the next departures on a Live Activity, e.g. '…, later departures, 15 minutes, 22 minutes'.")))
            segments.append(contentsOf: later.map { .countdown($0.departureDate) })
        }

        if isStale {
            segments.append(.text(LiveActivityStaleChrome.warningText))
        }

        return segments
    }

    /// The segments resolved to a string at `now`. Tests use this; so does
    /// anything that can't tick.
    public static func spokenString(_ segments: [SpokenSegment], now: Date) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text
            case .countdown(let departure): TripCountdownFormatStyle.spoken(departure: departure).format(now)
            }
        }
        .joined(separator: ", ")
    }

    private func temporalState(minutes: Int) -> TemporalState {
        if minutes < 0 { return .past }
        if minutes == 0 { return .present }
        return .future
    }
}
