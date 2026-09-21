//
//  WidgetTimelinePlanner.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Decides *when* a departures widget shows a new entry and *when* it asks
/// WidgetKit for fresh data. Pure date arithmetic: no WidgetKit, no network.
///
/// The two are different things, and conflating them is expensive. WidgetKit
/// budgets a widget 40–70 reloads a **day**. A reload keyed to the next
/// departure asks for one every few minutes on a frequent route and is
/// throttled within the hour. So: reload on a slow, fixed cadence, and have
/// each reload emit an entry at every departure boundary it already knows
/// about. The display advances as buses leave, at no cost to the budget.
public struct WidgetTimelinePlanner: Sendable {
    public struct Plan: Equatable, Sendable {
        /// When each timeline entry takes effect. Always starts with `now`.
        /// An entry dated `d` shows only departures strictly after `d` — see
        /// `departures(_:visibleAt:)`.
        /// Entries are at least `minimumEntrySpacing` apart: a departure that
        /// falls sooner than that after the previous entry is deferred to the
        /// spacing, not dropped.
        public let entryDates: [Date]

        /// When to ask WidgetKit for a reload (`.after(reloadDate)`).
        public let reloadDate: Date
    }

    /// 30 min × 18 waking hours = 36 reloads a day, under the 40–70 budget
    /// with room left for reloads the app triggers itself.
    static let reloadIntervalWithDepartures: TimeInterval = 30 * 60

    /// Nothing is coming in the fetched window, so look again less often.
    static let reloadIntervalWithoutDepartures: TimeInterval = 60 * 60

    private let minimumEntrySpacing: TimeInterval
    private let maximumEntries: Int

    /// - Parameter minimumEntrySpacing: Apple recommends entries "at least
    ///   about 5 minutes apart". A multi-bookmark widget has dense boundaries
    ///   and keeps the default; pass 0 for one entry per departure.
    public init(minimumEntrySpacing: TimeInterval = 5 * 60, maximumEntries: Int = 12) {
        self.minimumEntrySpacing = minimumEntrySpacing
        self.maximumEntries = max(1, maximumEntries)
    }

    public func plan(departureDates: [Date], now: Date) -> Plan {
        let upcoming = Set(departureDates.filter { $0 > now }).sorted()

        let interval = upcoming.isEmpty ? Self.reloadIntervalWithoutDepartures : Self.reloadIntervalWithDepartures
        let reloadDate = now.addingTimeInterval(interval)

        var entryDates = [now]
        for boundary in upcoming {
            guard entryDates.count < maximumEntries, let last = entryDates.last else { break }

            // An entry at or after this departure already drops it.
            guard boundary > last else { continue }

            // Too soon after the last entry: defer to the spacing rather than
            // drop the boundary, so a bus that has left lingers for at most
            // `minimumEntrySpacing` — not until some later departure happens
            // to clear the threshold.
            let entry = max(boundary, last.addingTimeInterval(minimumEntrySpacing))
            guard entry < reloadDate else { break }
            entryDates.append(entry)
        }

        return Plan(entryDates: entryDates, reloadDate: reloadDate)
    }
}

extension WidgetTimelinePlanner {
    /// The departures a timeline entry dated `entryDate` should show: those
    /// strictly after it.
    ///
    /// Strictly, because an undeferred entry is dated exactly at a departure —
    /// that entry exists to take that bus off the screen. `>=` would keep it
    /// there until the next boundary, which on a sparse route is the whole
    /// reload interval.
    public static func departures(_ departures: [ArrivalDeparture], visibleAt entryDate: Date) -> [ArrivalDeparture] {
        departures.filter { $0.arrivalDepartureDate > entryDate }
    }
}
