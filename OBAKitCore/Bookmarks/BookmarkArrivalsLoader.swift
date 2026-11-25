//
//  BookmarkArrivalsLoader.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What a caller wants arrivals for: a stop, and optionally one trip at it.
public struct BookmarkArrivalsRequest: Hashable, Sendable {
    public let stopID: StopID
    public let tripKey: TripBookmarkKey?

    public init(stopID: StopID, tripKey: TripBookmarkKey? = nil) {
        self.stopID = stopID
        self.tripKey = tripKey
    }

    public init(bookmark: Bookmark) {
        self.init(stopID: bookmark.stopID, tripKey: TripBookmarkKey(bookmark: bookmark))
    }

    public init(watchBookmark: WatchBookmark) {
        self.init(stopID: watchBookmark.stopID, tripKey: TripBookmarkKey(watchBookmark: watchBookmark))
    }

    /// The part of a stop's arrivals this request is about: one trip's
    /// departures for a trip request, every upcoming departure (soonest first)
    /// for a stop request.
    public func matching(_ arrivals: [ArrivalDeparture]) -> [ArrivalDeparture] {
        if let tripKey {
            return arrivals.tripKeyGroupedElements[tripKey] ?? []
        }

        return arrivals
            .filter { $0.temporalState != .past }
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
    }
}

/// Fetches arrivals for a set of bookmarks. Stateless: no timer, no cache, no
/// `CoreApplication`. The iOS app's `BookmarkDataLoader`, the iOS widget, and
/// (later) the watch app and its widget all call this.
public struct BookmarkArrivalsLoader: Sendable {
    private let minutesBefore: UInt
    private let minutesAfter: UInt
    private let savedArrivals: SavedArrivalsStore?

    /// - Parameter savedArrivals: When set, each stop's successful response is
    ///   saved there, and a stop that can't be fetched for lack of a connection
    ///   fails with a `SavedArrivalsFallback` carrying its saved arrivals.
    public init(minutesBefore: UInt = 0, minutesAfter: UInt = 60, savedArrivals: SavedArrivalsStore? = nil) {
        self.minutesBefore = minutesBefore
        self.minutesAfter = minutesAfter
        self.savedArrivals = savedArrivals
    }

    /// Streams one result per *distinct stop*, as each fetch lands.
    ///
    /// Requests are deduplicated by stop ID: two trip bookmarks at one stop
    /// cost one network call. A failure is delivered, not thrown, so one bad
    /// stop cannot cost the others their data; callers decide what a given
    /// error means. The stream finishes after the last stop reports.
    public func arrivals(
        for requests: [BookmarkArrivalsRequest],
        using apiService: RESTAPIService
    ) -> AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)> {
        var seen = Set<StopID>()
        let stopIDs = requests.map(\.stopID).filter { seen.insert($0).inserted }
        let (stream, continuation) = AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)>.makeStream()

        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for stopID in stopIDs {
                    group.addTask {
                        do {
                            let arrivals = try await fetchArrivals(stopID: stopID, using: apiService)
                            continuation.yield((stopID, .success(arrivals)))
                            // After the yield, so the departures on screen
                            // don't wait on it.
                            await saveTodaysScheduleIfNeeded(stopID: stopID, using: apiService)
                        } catch {
                            let fallback = savedArrivalsFallback(stopID: stopID, error: error, using: apiService)
                            continuation.yield((stopID, .failure(fallback ?? error)))
                        }
                    }
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }

        return stream
    }

    private func fetchArrivals(stopID: StopID, using apiService: RESTAPIService) async throws -> [ArrivalDeparture] {
        guard let savedArrivals, let regionID = apiService.regionIdentifier else {
            return try await apiService.getArrivalsAndDeparturesForStop(
                id: stopID,
                minutesBefore: minutesBefore,
                minutesAfter: minutesAfter
            ).entry.arrivalsAndDepartures
        }

        let (response, body) = try await apiService.getArrivalsAndDeparturesForStopKeepingBody(
            id: stopID,
            minutesBefore: minutesBefore,
            minutesAfter: minutesAfter
        )
        if let body {
            savedArrivals.save(body, stopID: stopID, regionID: regionID)
        }
        return response.entry.arrivalsAndDepartures
    }

    /// Saves the stop's timetable for today, unless one was already saved
    /// today: a day's timetable doesn't change, so one fetch per stop per day
    /// is enough. A failure is logged; the next good fetch tries again.
    private func saveTodaysScheduleIfNeeded(stopID: StopID, using apiService: RESTAPIService) async {
        guard let savedArrivals, let regionID = apiService.regionIdentifier else { return }
        if let saved = savedArrivals.load(kind: .schedule, stopID: stopID, regionID: regionID),
           Calendar.current.isDateInToday(saved.savedAt) {
            return
        }

        do {
            let (_, body) = try await apiService.getScheduleForStopKeepingBody(stopID: stopID)
            savedArrivals.save(body, kind: .schedule, stopID: stopID, regionID: regionID)
        } catch {
            if error.isCancellation { return }
            Logger.error("BookmarkArrivalsLoader: timetable for stop \(stopID) failed: \(error.localizedDescription)")
        }
    }

    /// What was saved for the stop, when `error` means the device couldn't
    /// reach the server and something was. Any other failure (the server
    /// erred, the stop is gone) is not about the connection, so saved data
    /// would only hide it.
    private func savedArrivalsFallback(stopID: StopID, error: Error, using apiService: RESTAPIService) -> SavedArrivalsFallback? {
        guard
            let savedArrivals,
            let regionID = apiService.regionIdentifier,
            [.offline, .timeout].contains(ErrorClassifier.category(for: error))
        else {
            return nil
        }

        let savedLive = savedArrivals.load(stopID: stopID, regionID: regionID)
        let liveArrivals = savedLive.flatMap {
            try? apiService.decodeKeptBody(StopArrivals.self, from: $0.body).entry.arrivalsAndDepartures
        }
        let savedSchedule = savedArrivals.load(kind: .schedule, stopID: stopID, regionID: regionID)
        let schedule = savedSchedule.flatMap {
            try? apiService.decodeKeptBody(ScheduleForStop.self, from: $0.body).entry
        }

        guard let savedAt = (liveArrivals != nil ? savedLive?.savedAt : nil) ?? (schedule != nil ? savedSchedule?.savedAt : nil) else {
            return nil
        }

        // A live fetch asks for no minutes before now, so it never returns a
        // departure that has left. Saved ones age, so drop those that have.
        // Their trips still count for the timetable: one that left ahead of
        // its timetable time must not come back as scheduled.
        let savedTripIDs = Set((liveArrivals ?? []).map(\.tripID))
        return SavedArrivalsFallback(
            arrivals: (liveArrivals ?? []).filter { $0.temporalState != .past },
            savedAt: savedAt,
            scheduledDepartures: (schedule?.scheduledDepartures ?? []).filter { $0.minutes >= 0 && !savedTripIDs.contains($0.tripID) },
            underlyingError: error
        )
    }

    /// Collects the stream into per-bookmark departures. A bookmark whose stop
    /// failed has **no entry** — distinct from an empty array, which means the
    /// fetch worked and nothing is coming.
    public func departuresByBookmark(
        for bookmarks: [Bookmark],
        using apiService: RESTAPIService
    ) async -> [UUID: [ArrivalDeparture]] {
        let requests = bookmarks.map { ($0.id, BookmarkArrivalsRequest(bookmark: $0)) }

        var arrivalsByStop = [StopID: [ArrivalDeparture]]()
        for await (stopID, result) in arrivals(for: requests.map(\.1), using: apiService) {
            switch result {
            case .success(let arrivals):
                arrivalsByStop[stopID] = arrivals
            case .failure(let error):
                Logger.error("BookmarkArrivalsLoader: arrivals failed for stop \(stopID): \(error.localizedDescription)")
            }
        }

        var result = [UUID: [ArrivalDeparture]]()
        for (bookmarkID, request) in requests {
            if let arrivals = arrivalsByStop[request.stopID] {
                result[bookmarkID] = request.matching(arrivals)
            }
        }
        return result
    }
}

extension RESTAPIService {
    /// Builds a service for `region` without a `CoreApplication`.
    ///
    /// For extensions. `CoreApplication.init` starts a regions fetch, opens the
    /// stop cache, and increments the launch counter that survey gating reads —
    /// none of which a timeline reload should pay for or cause. Do not reach for
    /// `CoreAppConfig(appBundle:)` instead: it builds a `CLLocationManager`.
    public static func standalone(
        region: Region,
        apiKey: String,
        appVersion: String,
        uuid: String,
        dataLoader: URLDataLoader = URLSession.shared,
        retryPolicy: RetryPolicy = .disabled
    ) -> RESTAPIService {
        RESTAPIService(
            APIServiceConfiguration(
                baseURL: region.OBABaseURL,
                apiKey: apiKey,
                uuid: uuid,
                appVersion: appVersion,
                regionIdentifier: region.regionIdentifier
            ),
            dataLoader: dataLoader,
            retryPolicy: retryPolicy
        )
    }
}
