//
//  NextDeparturesCardModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// What the Next Departures card shows for an outcome (#1554): pure, so every
/// outcome's text and buttons are testable without App Intents or SwiftUI.
///
/// The card repeats nothing the dialog doesn't say. With departures it shows
/// the bookmark, its route and headsign, and up to
/// `NextDeparturesSummary.maximumDepartures` departures; for every other
/// outcome it shows the same localized sentence the dialog speaks.
struct NextDeparturesCardModel: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int
        /// "5m", or "NOW" — the bookmark card's chip text.
        let timeText: String
        /// The adherence label: "on time", "3 min late", or "schedule data".
        /// Shown in words as well as color, so color is never the only signal.
        let statusText: String
        let status: DepartureStatus
        /// "in 5 minutes, live tracking, on time", for VoiceOver.
        let accessibilityLabel: String

        static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.id == rhs.id && lhs.timeText == rhs.timeText && lhs.statusText == rhs.statusText && lhs.accessibilityLabel == rhs.accessibilityLabel
        }
    }

    /// The bookmark the card is about; `nil` for an answer about no bookmark.
    let bookmarkName: String?
    let routeShortName: String?
    let headsign: String?
    let rows: [Row]
    /// The dialog's sentence, shown when there are no departure rows.
    let message: String?
    /// Shown whenever re-fetching could change the card: with departures,
    /// after a failed load, and when nothing is coming yet. Hidden for no
    /// bookmarks, no region, and an unavailable bookmark, which no fetch
    /// can fix.
    let showsRefresh: Bool
    /// Track starts the bookmark's Live Activity, so it needs a departure to
    /// follow and Live Activities turned on for the app.
    let showsTrack: Bool

    /// - Parameter liveActivitiesEnabled: `ActivityAuthorizationInfo().areActivitiesEnabled`.
    init(outcome: NextDeparturesSummary.Outcome, now: Date, liveActivitiesEnabled: Bool = false) {
        guard case let .departures(bookmarkName, routeShortName, headsign, departures) = outcome else {
            self.bookmarkName = nil
            self.routeShortName = nil
            self.headsign = nil
            self.rows = []
            self.message = NextDeparturesSummary.text(for: outcome, now: now)
            self.showsTrack = false
            if case .loadFailed = outcome {
                self.showsRefresh = true
            } else {
                self.showsRefresh = false
            }
            return
        }

        let rows = Self.rows(for: departures, now: now)
        self.bookmarkName = bookmarkName
        self.showsRefresh = true
        self.showsTrack = !rows.isEmpty && liveActivitiesEnabled
        if rows.isEmpty {
            self.routeShortName = nil
            self.headsign = nil
            self.rows = []
            self.message = NextDeparturesSummary.text(for: outcome, now: now)
        } else {
            self.routeShortName = routeShortName
            self.headsign = headsign
            self.rows = rows
            self.message = nil
        }
    }

    /// The departures still to come, soonest first, as `NextDeparturesSummary`
    /// counts them, so the card and the dialog agree on which three.
    private static func rows(for departures: [NextDeparturesSummary.Departure], now: Date) -> [Row] {
        departures
            .sorted { $0.date < $1.date }
            .map { (departure: $0, minutes: Int($0.date.timeIntervalSince(now) / 60)) }
            .filter { $0.minutes >= 0 }
            .prefix(NextDeparturesSummary.maximumDepartures)
            .enumerated()
            .map { index, item in
                let status = DepartureStatus(isRealTime: item.departure.isRealTime, scheduleStatus: item.departure.scheduleStatus, deviationMinutes: item.departure.deviationMinutes)
                let timeText = item.minutes == 0
                    ? OBALoc("stop_page.countdown.now", value: "NOW", comment: "Shown in place of the minutes countdown when the vehicle is departing now")
                    : Formatters.shortMinutesText(item.minutes)
                let spokenTime = NextDeparturesSummary.relativeTime(minutes: item.minutes)
                return Row(
                    id: index,
                    timeText: timeText,
                    statusText: status.label,
                    status: status,
                    accessibilityLabel: "\(spokenTime), \(status.accessibilityStatusDescription)"
                )
            }
    }
}
