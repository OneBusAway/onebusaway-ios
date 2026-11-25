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
    /// Each watch bookmark's next departure after `now`, yielded once every
    /// bookmarked stop has reported. A bookmark whose stop failed with nothing
    /// saved has no entry. When the watch can't reach the server, saved
    /// departures stand in for live ones, if this loader has a store.
    ///
    /// Yields as soon as the last stop reports rather than when the loader's
    /// stream ends: the loader saves the day's timetable for each stop after
    /// reporting it, and the rows must not wait for those downloads. The
    /// stream keeps draining after the yield so those saves can finish.
    public func nextDeparturesByWatchBookmark(
        for bookmarks: [WatchBookmark],
        using apiService: RESTAPIService,
        now: Date = Date()
    ) -> AsyncStream<[UUID: WatchBookmarkDeparture]> {
        let requests = bookmarks.map { ($0.id, BookmarkArrivalsRequest(watchBookmark: $0)) }
        let (stream, continuation) = AsyncStream<[UUID: WatchBookmarkDeparture]>.makeStream()

        let task = Task {
            var departures = [UUID: WatchBookmarkDeparture]()
            var pendingStops = Set(requests.map(\.1.stopID))
            for await (stopID, result) in arrivals(for: requests.map(\.1), using: apiService) {
                for (bookmarkID, request) in requests where request.stopID == stopID {
                    if let departure = Self.departure(for: request, result: result, now: now) {
                        departures[bookmarkID] = departure
                    }
                }
                pendingStops.remove(stopID)
                if pendingStops.isEmpty {
                    continuation.yield(departures)
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }

        return stream
    }

    /// What one stop's result means for a bookmark at it: the next live
    /// departure, or offline, the next saved one, then the next timetable trip
    /// for the bookmark's route and headsign. `nil` when the stop failed with
    /// nothing saved.
    private static func departure(
        for request: BookmarkArrivalsRequest,
        result: Result<[ArrivalDeparture], Error>,
        now: Date
    ) -> WatchBookmarkDeparture? {
        switch result {
        case .success(let arrivals):
            return WatchBookmarkDeparture(arrival: request.nextArrival(in: arrivals, after: now))
        case .failure(let fallback as SavedArrivalsFallback):
            if let arrival = request.nextArrival(in: fallback.arrivals, after: now) {
                return WatchBookmarkDeparture(arrival: arrival, savedAt: fallback.savedAt)
            }
            let scheduled = fallback.scheduledDepartures.first { departure in
                departure.date > now && request.tripKey.map { departure.matches($0) } ?? true
            }
            return WatchBookmarkDeparture(scheduledDeparture: scheduled, savedAt: fallback.savedAt)
        case .failure(let error):
            Logger.error("BookmarkArrivalsLoader: arrivals failed for stop \(request.stopID): \(error.localizedDescription)")
            return nil
        }
    }
}

private extension BookmarkArrivalsRequest {
    func nextArrival(in arrivals: [ArrivalDeparture], after now: Date) -> ArrivalDeparture? {
        matching(arrivals).first { $0.arrivalDepartureDate > now }
    }
}
