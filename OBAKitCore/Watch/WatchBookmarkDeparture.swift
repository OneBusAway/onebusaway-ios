//
//  WatchBookmarkDeparture.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The next departure a watch bookmark row shows. Offline, it's the next saved
/// departure, or once those have all left, the next one in the stop's saved
/// timetable.
public struct WatchBookmarkDeparture: Equatable, Sendable {
    /// The next live or saved departure.
    public let arrival: ArrivalDeparture?

    /// Offline with no saved departure left: the next timetable departure.
    public let scheduledDeparture: ScheduledDeparture?

    /// When the departure shown was saved, while the watch can't reach the
    /// server; `nil` while it's live.
    public let savedAt: Date?

    public init(arrival: ArrivalDeparture? = nil, scheduledDeparture: ScheduledDeparture? = nil, savedAt: Date? = nil) {
        self.arrival = arrival
        self.scheduledDeparture = scheduledDeparture
        self.savedAt = savedAt
    }

    /// When the departure shown leaves.
    public var date: Date? {
        arrival?.arrivalDepartureDate ?? scheduledDeparture?.date
    }
}

extension BookmarkArrivalsLoader {
    /// Each watch bookmark's next departure after `now`. When the watch can't
    /// reach the server, saved departures stand in for live ones, if this
    /// loader has a store. A bookmark whose stop failed with nothing saved has
    /// no entry.
    public func nextDeparturesByWatchBookmark(
        for bookmarks: [WatchBookmark],
        using apiService: RESTAPIService,
        now: Date = Date()
    ) async -> [UUID: WatchBookmarkDeparture] {
        let requests = bookmarks.map { ($0.id, BookmarkArrivalsRequest(watchBookmark: $0)) }

        var resultsByStop = [StopID: Result<[ArrivalDeparture], Error>]()
        for await (stopID, result) in arrivals(for: requests.map(\.1), using: apiService) {
            resultsByStop[stopID] = result
        }

        var departures = [UUID: WatchBookmarkDeparture]()
        for (bookmarkID, request) in requests {
            switch resultsByStop[request.stopID] {
            case .success(let arrivals):
                departures[bookmarkID] = WatchBookmarkDeparture(arrival: request.nextArrival(in: arrivals, after: now))
            case .failure(let fallback as SavedArrivalsFallback):
                if let arrival = request.nextArrival(in: fallback.arrivals, after: now) {
                    departures[bookmarkID] = WatchBookmarkDeparture(arrival: arrival, savedAt: fallback.savedAt)
                } else {
                    let scheduled = fallback.scheduledDepartures.first { departure in
                        departure.date > now && request.tripKey.map { departure.matches($0) } ?? true
                    }
                    departures[bookmarkID] = WatchBookmarkDeparture(scheduledDeparture: scheduled, savedAt: fallback.savedAt)
                }
            case .failure(let error):
                Logger.error("BookmarkArrivalsLoader: arrivals failed for stop \(request.stopID): \(error.localizedDescription)")
            case nil:
                break
            }
        }
        return departures
    }
}

private extension BookmarkArrivalsRequest {
    func nextArrival(in arrivals: [ArrivalDeparture], after now: Date) -> ArrivalDeparture? {
        matching(arrivals).first { $0.arrivalDepartureDate > now }
    }
}
