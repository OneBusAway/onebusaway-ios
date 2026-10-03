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

    private func temporalState(minutes: Int) -> TemporalState {
        if minutes < 0 { return .past }
        if minutes == 0 { return .present }
        return .future
    }
}
