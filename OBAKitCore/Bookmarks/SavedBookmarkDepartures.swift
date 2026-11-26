//
//  SavedBookmarkDepartures.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Each bookmark's departures: live where its stop could be fetched, and what
/// was saved for the stop where the device couldn't reach the server.
public struct SavedBookmarkDepartures: Sendable {
    /// Departures keyed by `Bookmark.id`. A bookmark whose stop failed with
    /// nothing saved has no entry, as in `departuresByBookmark(for:using:)`.
    /// For a saved stop these are the saved departures that haven't left.
    public let departures: [UUID: [ArrivalDeparture]]

    /// For each bookmark shown from saved data, the saved timetable's
    /// departures that haven't left: all of the stop's, or a trip bookmark's
    /// own route and headsign. Live bookmarks have no entry, so an entry, even
    /// an empty one, means the bookmark is offline.
    public let scheduledDepartures: [UUID: [ScheduledDeparture]]

    /// When the oldest saved data shown was saved; `nil` when every stop was live.
    public let savedAt: Date?
}

extension BookmarkArrivalsLoader {
    /// Like `departuresByBookmark(for:using:)`, except that a stop the device
    /// couldn't reach shows what the loader's store saved for it.
    public func departuresByBookmarkKeepingSaved(
        for bookmarks: [Bookmark],
        using apiService: RESTAPIService
    ) async -> SavedBookmarkDepartures {
        let requests = bookmarks.map { ($0.id, BookmarkArrivalsRequest(bookmark: $0)) }

        var arrivalsByStop = [StopID: [ArrivalDeparture]]()
        var fallbacksByStop = [StopID: SavedArrivalsFallback]()
        for await (stopID, result) in arrivals(for: requests.map(\.1), using: apiService) {
            switch result {
            case .success(let arrivals):
                arrivalsByStop[stopID] = arrivals
            case .failure(let fallback as SavedArrivalsFallback):
                Logger.info("BookmarkArrivalsLoader: showing saved arrivals for stop \(stopID): \(fallback.underlyingError.localizedDescription)")
                fallbacksByStop[stopID] = fallback
            case .failure(let error):
                Logger.error("BookmarkArrivalsLoader: arrivals failed for stop \(stopID): \(error.localizedDescription)")
            }
        }

        var departures = [UUID: [ArrivalDeparture]]()
        var scheduledDepartures = [UUID: [ScheduledDeparture]]()
        for (bookmarkID, request) in requests {
            if let arrivals = arrivalsByStop[request.stopID] {
                departures[bookmarkID] = request.matching(arrivals)
            } else if let fallback = fallbacksByStop[request.stopID] {
                departures[bookmarkID] = request.matching(fallback.arrivals)
                scheduledDepartures[bookmarkID] = request.tripKey.map { key in
                    fallback.scheduledDepartures.filter { $0.matches(key, timetableHeadsigns: fallback.timetableHeadsigns[key] ?? []) }
                } ?? fallback.scheduledDepartures
            }
        }

        return SavedBookmarkDepartures(
            departures: departures,
            scheduledDepartures: scheduledDepartures,
            savedAt: fallbacksByStop.values.map(\.savedAt).min()
        )
    }
}
