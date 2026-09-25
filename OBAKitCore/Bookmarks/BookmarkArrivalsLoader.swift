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

    public init(minutesBefore: UInt = 0, minutesAfter: UInt = 60) {
        self.minutesBefore = minutesBefore
        self.minutesAfter = minutesAfter
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
        let (minutesBefore, minutesAfter) = (self.minutesBefore, self.minutesAfter)

        let (stream, continuation) = AsyncStream<(StopID, Result<[ArrivalDeparture], Error>)>.makeStream()

        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for stopID in stopIDs {
                    group.addTask {
                        do {
                            let arrivals = try await apiService.getArrivalsAndDeparturesForStop(
                                id: stopID,
                                minutesBefore: minutesBefore,
                                minutesAfter: minutesAfter
                            ).entry.arrivalsAndDepartures
                            continuation.yield((stopID, .success(arrivals)))
                        } catch {
                            continuation.yield((stopID, .failure(error)))
                        }
                    }
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in task.cancel() }

        return stream
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
        dataLoader: URLDataLoader = URLSession.shared
    ) -> RESTAPIService {
        RESTAPIService(
            APIServiceConfiguration(
                baseURL: region.OBABaseURL,
                apiKey: apiKey,
                uuid: uuid,
                appVersion: appVersion,
                regionIdentifier: region.regionIdentifier
            ),
            dataLoader: dataLoader
        )
    }
}
