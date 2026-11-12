//
//  NextDepartureComplication.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Widget family abstraction used to share per-family bookmark limits across
/// iOS widgets, watchOS complications, and unit tests without importing WidgetKit
/// into `OBAKitCore`.
public enum WidgetBookmarkFamily: Equatable, Sendable {
    case systemMedium
    case systemLarge
    case accessoryCircular
    case accessoryRectangular
    case accessoryInline
    case other

    /// Maximum number of bookmarks a timeline provider should load and render
    /// for this family so reloads never fetch stops that cannot be displayed.
    public var maximumBookmarks: Int {
        switch self {
        case .systemLarge:
            return 7
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return 1
        case .systemMedium, .other:
            return 2
        }
    }
}

/// Platform-neutral bookmark metadata needed to render a next-departure
/// complication from a `Bookmark`.
public struct NextDepartureComplicationBookmark: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let stopID: StopID
    public let stopName: String
    public let regionIdentifier: Int
    public let routeShortName: String?
    public let tripHeadsign: String?
    public let isTripBookmark: Bool
    public let isFavorite: Bool

    public init(
        id: UUID,
        name: String,
        stopID: StopID,
        stopName: String,
        regionIdentifier: Int,
        routeShortName: String? = nil,
        tripHeadsign: String? = nil,
        isTripBookmark: Bool = false,
        isFavorite: Bool = true
    ) {
        self.id = id
        self.name = name
        self.stopID = stopID
        self.stopName = stopName
        self.regionIdentifier = regionIdentifier
        self.routeShortName = String.nilifyBlankValue(routeShortName)
        self.tripHeadsign = String.nilifyBlankValue(tripHeadsign)
        self.isTripBookmark = isTripBookmark
        self.isFavorite = isFavorite
    }

    public init(bookmark: Bookmark) {
        self.init(
            id: bookmark.id,
            name: bookmark.name,
            stopID: bookmark.stopID,
            stopName: bookmark.stop.name,
            regionIdentifier: bookmark.regionIdentifier,
            routeShortName: bookmark.routeShortName,
            tripHeadsign: bookmark.tripHeadsign,
            isTripBookmark: bookmark.isTripBookmark,
            isFavorite: bookmark.isFavorite
        )
    }

    /// Concise title suitable for narrow complication fallback layouts.
    public var displayTitle: String {
        if isTripBookmark, let routeShortName {
            return routeShortName
        }
        return String.nilifyBlankValue(name) ?? stopName
    }
}

/// Resolved presentation data for the next upcoming departure on a complication.
public struct ComplicationDeparture: Equatable, Sendable {
    public let routeShortName: String
    public let headsign: String
    public let departureDate: Date
    public let isRealTime: Bool
    public let scheduleStatus: ScheduleStatus
    public let routeColorHex: String?
    public let routeTextColorHex: String?
    public let stopName: String
    public let bookmarkName: String

    public init(
        routeShortName: String,
        headsign: String,
        departureDate: Date,
        isRealTime: Bool,
        scheduleStatus: ScheduleStatus,
        routeColorHex: String? = nil,
        routeTextColorHex: String? = nil,
        stopName: String,
        bookmarkName: String
    ) {
        self.routeShortName = routeShortName
        self.headsign = headsign
        self.departureDate = departureDate
        self.isRealTime = isRealTime
        self.scheduleStatus = scheduleStatus
        self.routeColorHex = routeColorHex
        self.routeTextColorHex = routeTextColorHex
        self.stopName = stopName
        self.bookmarkName = bookmarkName
    }

    public init(arrivalDeparture: ArrivalDeparture, bookmark: NextDepartureComplicationBookmark) {
        let resolvedRoute = arrivalDeparture.safeRouteShortName
            ?? bookmark.routeShortName
            ?? bookmark.name
        let resolvedHeadsign = arrivalDeparture.safeTripHeadsign
            ?? bookmark.tripHeadsign
            ?? String.nilifyBlankValue(bookmark.stopName)
            ?? bookmark.name

        self.init(
            routeShortName: resolvedRoute,
            headsign: resolvedHeadsign,
            departureDate: arrivalDeparture.departureDate,
            isRealTime: arrivalDeparture.predicted,
            scheduleStatus: arrivalDeparture.scheduleStatus,
            routeColorHex: arrivalDeparture.safeRouteColorHex,
            routeTextColorHex: arrivalDeparture.safeRouteTextColorHex,
            stopName: bookmark.stopName,
            bookmarkName: bookmark.name
        )
    }

    /// Whole minutes remaining until `departureDate` at `now`, clamped to 0.
    public func minutesUntil(at now: Date) -> Int {
        max(0, Int(departureDate.timeIntervalSince(now) / 60.0))
    }

    /// `true` when less than a full minute remains before departure (shown as "NOW").
    public func isArrivingNow(at now: Date) -> Bool {
        departureDate.timeIntervalSince(now) < 60.0
    }

    /// Localized static countdown string (`"NOW"` or `"8m"`).
    public func shortCountdownText(at now: Date) -> String {
        TripCountdownFormatStyle(departure: departureDate).format(now)
    }

    /// Static snapshot matching the complication's live countdown display (`"NOW"` when < 1 min, else `"8m"`).
    public func countdownSnapshot(at now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        if isArrivingNow(at: now) {
            return shortCountdownText(at: now)
        }
        return TickingCountdownText.snapshot(departure: departureDate, now: now, locale: locale)
    }

    /// Spoken VoiceOver description combining route, headsign, countdown, clock time, and stop name.
    public func spokenAccessibilityLabel(
        at now: Date,
        formatters: Formatters,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let routeAndHeadsign = "\(routeShortName) \(headsign)"
        let routeLabel = formatters.accessibilityLabelForArrivalDeparture(routeAndHeadsign: routeAndHeadsign)
        let countdown = TickingCountdownText.spokenSnapshot(departure: departureDate, now: now, locale: locale)
        let clockTime = formatters.timeFormatter.string(from: departureDate)
        return "\(routeLabel), \(countdown), \(clockTime), \(stopName)"
    }
}

/// Exhaustive presentation state for a next-departure complication.
public enum NextDepartureComplicationState: Equatable, Sendable {
    case noBookmarks
    case unavailable(bookmark: NextDepartureComplicationBookmark)
    case noDepartures(bookmark: NextDepartureComplicationBookmark)
    case departure(ComplicationDeparture, bookmark: NextDepartureComplicationBookmark)

    /// The primary bookmark associated with this state, if any.
    public var bookmark: NextDepartureComplicationBookmark? {
        switch self {
        case .noBookmarks:
            return nil
        case .unavailable(let bookmark),
             .noDepartures(let bookmark),
             .departure(_, let bookmark):
            return bookmark
        }
    }

    /// The resolved departure when available.
    public var departure: ComplicationDeparture? {
        guard case .departure(let departure, _) = self else { return nil }
        return departure
    }
}

/// Pure selection and formatting logic for the Next Departure complication.
public enum NextDepartureComplication {
    /// Resolves the complication state for the primary bookmark in `bookmarks` at `now`.
    public static func resolve(
        bookmarks: [NextDepartureComplicationBookmark],
        departuresByBookmark: [UUID: [ArrivalDeparture]],
        now: Date
    ) -> NextDepartureComplicationState {
        guard let bookmark = bookmarks.first else {
            return .noBookmarks
        }

        guard let departures = departuresByBookmark[bookmark.id] else {
            return .unavailable(bookmark: bookmark)
        }

        let upcoming = departures
            .filter { $0.departureEnabled && $0.hasPlausibleDepartureDate && $0.departureDate > now }
            .min { $0.departureDate < $1.departureDate }

        guard let upcoming else {
            return .noDepartures(bookmark: bookmark)
        }

        return .departure(ComplicationDeparture(arrivalDeparture: upcoming, bookmark: bookmark), bookmark: bookmark)
    }

    /// Convenience overload for iOS `Bookmark` entries.
    public static func resolve(
        bookmarks: [Bookmark],
        departuresByBookmark: [UUID: [ArrivalDeparture]],
        now: Date
    ) -> NextDepartureComplicationState {
        resolve(
            bookmarks: bookmarks.map(NextDepartureComplicationBookmark.init(bookmark:)),
            departuresByBookmark: departuresByBookmark,
            now: now
        )
    }

    /// Single-line text snapshot for `.accessoryInline` complications and unit tests.
    public static func inlineSummary(
        for state: NextDepartureComplicationState,
        now: Date,
        noBookmarksText: String,
        noDeparturesText: String,
        unavailableText: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch state {
        case .noBookmarks:
            return noBookmarksText
        case .unavailable(let bookmark):
            return "\(bookmark.displayTitle) · \(unavailableText)"
        case .noDepartures(let bookmark):
            return "\(bookmark.displayTitle) · \(noDeparturesText)"
        case .departure(let departure, _):
            let countdown = departure.countdownSnapshot(at: now, locale: locale)
            return "\(departure.routeShortName) · \(countdown) · \(departure.headsign)"
        }
    }
}
