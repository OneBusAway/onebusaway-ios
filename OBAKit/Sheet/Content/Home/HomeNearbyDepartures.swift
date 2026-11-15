//
//  HomeNearbyDepartures.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// A departure from a stop near the map's center: the next one of its route and
/// headsign from that stop.
struct HomeNearbyDeparture {
    let stop: Stop
    let arrivalDeparture: ArrivalDeparture
}

/// A row of the home sheet's Nearby section.
enum HomeNearbyRow: Identifiable, Equatable {
    case departure(HomeNearbyDeparture)
    /// A stop with nothing to list yet, or nothing at all: its arrivals haven't
    /// loaded, or it has no departures coming.
    case stop(Stop)

    var id: String {
        switch self {
        case .departure(let departure):
            let arrival = departure.arrivalDeparture
            // Every field of `TripBookmarkKey`, which is what makes a stop's
            // departures distinct: two can share a route and headsign and differ
            // in the short name they run under.
            return "departure|\(departure.stop.id)|\(arrival.routeID)|\(arrival.routeShortName)|\(arrival.tripHeadsign ?? "")"
        case .stop(let stop):
            return "stop|\(stop.id)"
        }
    }

    var departure: HomeNearbyDeparture? {
        if case .departure(let departure) = self { departure } else { nil }
    }

    /// The same row showing the same thing: a departure's trip and time are part
    /// of it, so a countdown that moved is a change.
    static func == (lhs: HomeNearbyRow, rhs: HomeNearbyRow) -> Bool {
        switch (lhs, rhs) {
        case (.stop(let lhs), .stop(let rhs)):
            lhs.id == rhs.id
        case (.departure(let lhs), .departure(let rhs)):
            lhs.stop.id == rhs.stop.id
                && lhs.arrivalDeparture.tripID == rhs.arrivalDeparture.tripID
                && lhs.arrivalDeparture.arrivalDepartureDate == rhs.arrivalDeparture.arrivalDepartureDate
                && lhs.arrivalDeparture.arrivalDepartureMinutes == rhs.arrivalDeparture.arrivalDepartureMinutes
                && lhs.arrivalDeparture.scheduleStatus == rhs.arrivalDeparture.scheduleStatus
        default:
            false
        }
    }
}

/// The rules for the home sheet's Nearby section, which lists departures rather
/// than stop names: a rider opening the app near a stop wants to know what
/// leaves and when, and a stop's name answers neither.
enum HomeNearbyDepartures {

    /// How many of the nearest stops have their arrivals fetched. Each is a
    /// request every poll, so fewer than the section could list.
    static let stopLimit = 3

    /// Departures listed per stop, so the nearest one, if it's busy, doesn't
    /// push every other stop out of the section.
    static let perStopLimit = 2

    /// The section's rows for `stops`, nearest first.
    ///
    /// - Parameters:
    ///   - arrivals: Arrivals by stop, for the stops whose fetch has finished.
    ///     A stop missing from it hasn't loaded and shows as a stop.
    ///   - excluding: Departures the Bookmarks cards above already show.
    static func rows(
        stops: [Stop],
        arrivals: [StopID: [ArrivalDeparture]],
        excluding: Set<TripBookmarkKey>,
        limit: Int = HomeSheetSection.itemLimit,
        perStopLimit: Int = HomeNearbyDepartures.perStopLimit
    ) -> [HomeNearbyRow] {
        var rows: [HomeNearbyRow] = []

        for stop in stops {
            guard let loaded = arrivals[stop.id] else {
                rows.append(.stop(stop))
                continue
            }
            let departures = nextDepartures(from: loaded, excluding: excluding).prefix(perStopLimit)
            rows += departures.map { .departure(HomeNearbyDeparture(stop: stop, arrivalDeparture: $0)) }
        }

        // Nothing leaving anywhere nearby, or all of it bookmarked: the stops
        // themselves, so the section still leads somewhere.
        guard !rows.isEmpty else {
            return stops.prefix(limit).map { .stop($0) }
        }
        return Array(rows.prefix(limit))
    }

    /// The soonest upcoming departure of each route and headsign, soonest first.
    private static func nextDepartures(
        from arrivals: [ArrivalDeparture],
        excluding: Set<TripBookmarkKey>
    ) -> [ArrivalDeparture] {
        var soonest: [TripBookmarkKey: ArrivalDeparture] = [:]
        for arrival in arrivals where arrival.temporalState != .past {
            let key = TripBookmarkKey(arrivalDeparture: arrival)
            guard !excluding.contains(key) else { continue }
            if let current = soonest[key], current.arrivalDepartureDate <= arrival.arrivalDepartureDate { continue }
            soonest[key] = arrival
        }
        return soonest.values.sorted {
            if $0.arrivalDepartureDate != $1.arrivalDepartureDate {
                return $0.arrivalDepartureDate < $1.arrivalDepartureDate
            }
            // A stable order for departures at the same minute.
            return $0.tripID < $1.tripID
        }
    }
}

/// Loads arrivals for the few stops nearest the map's center and turns them into
/// the Nearby section's rows.
///
/// Unlike `HomeNearbyStopsSectionModel`, which re-slices stops the map already
/// has, this costs requests: up to `HomeNearbyDepartures.stopLimit` per staleness
/// window. So it fetches only while its rows are on screen (`isVisible`), keeps
/// what it has for a stop that stays nearby as the map moves, and fetches a stop
/// again only once its arrivals are stale.
@MainActor
final class HomeNearbyDeparturesSectionModel: ObservableObject {

    @Published private(set) var rows: [HomeNearbyRow] = []

    /// The stops nearest the map's center, nearest first. Only the first
    /// `HomeNearbyDepartures.stopLimit` are used.
    var stops: [Stop] = [] {
        didSet {
            let nearest = Array(stops.prefix(HomeNearbyDepartures.stopLimit))
            guard nearest.map(\.id) != self.nearest.map(\.id) else { return }
            self.nearest = nearest
            // Kept for a stop the map has moved off, while they're fresh: a pan
            // away and back shouldn't fetch it again. Past that they would only
            // pile up.
            let ids = Set(nearest.map(\.id))
            let now = Date()
            loaded = loaded.filter { ids.contains($0.key) || now.timeIntervalSince($0.value.date) <= Self.staleAfter }
            rebuildRows()
            loadIfNeeded()
        }
    }

    /// Whether the section's rows are on screen: Home is the tab showing, the
    /// sheet is raised far enough to show its list, and nothing covers it.
    var isVisible = false {
        didSet {
            guard isVisible, !oldValue else { return }
            loadIfNeeded()
        }
    }

    private struct Loaded {
        let arrivals: [ArrivalDeparture]
        let date: Date
    }

    private var nearest: [Stop] = []
    private var loaded: [StopID: Loaded] = [:]
    private var inFlight: Set<StopID> = []

    /// The fetch started last, for tests to wait on: setting `stops` or
    /// `isVisible` starts one without handing it back.
    private(set) var loadTask: Task<Void, Never>?

    private let fetch: (StopID) async throws -> [ArrivalDeparture]
    private let excludedKeys: () -> Set<TripBookmarkKey>

    /// - Parameters:
    ///   - fetch: A stop's upcoming arrivals and departures.
    ///   - excludedKeys: The departures the Bookmarks section shows, read at
    ///     each rebuild.
    init(
        fetch: @escaping (StopID) async throws -> [ArrivalDeparture],
        excludedKeys: @escaping () -> Set<TripBookmarkKey>
    ) {
        self.fetch = fetch
        self.excludedKeys = excludedKeys
    }

    /// How long a stop's arrivals stand before they're fetched again: the home
    /// sheet's poll interval.
    static let staleAfter: TimeInterval = 30

    /// How far ahead to look. Shorter than the stop page's: this lists what
    /// leaves next, and an hour covers that.
    static let minutesAfter: UInt = 60

    convenience init(application: Application, excludedKeys: @escaping () -> Set<TripBookmarkKey>) {
        self.init(
            fetch: { [weak application] stopID in
                guard let apiService = application?.apiService else { throw URLError(.cancelled) }
                return try await apiService.getArrivalsAndDeparturesForStop(
                    id: stopID,
                    minutesBefore: 0,
                    minutesAfter: Self.minutesAfter,
                    cachePolicy: FeatureFlags.realtimeCachePolicy(userDefaults: application?.userDefaults ?? .standard)
                ).entry.arrivalsAndDepartures
            },
            excludedKeys: excludedKeys
        )
    }

    /// Fetches arrivals for the nearest stops that have none or whose are stale.
    /// Returns the fetch, for tests to wait on, or `nil` when there was nothing
    /// to do: the rows are hidden, or every stop is fresh or already loading.
    @discardableResult
    func loadIfNeeded(now: Date = Date(), staleAfter: TimeInterval = HomeNearbyDeparturesSectionModel.staleAfter) -> Task<Void, Never>? {
        guard isVisible else { return nil }
        let due = nearest.map(\.id).filter { id in
            guard !inFlight.contains(id) else { return false }
            guard let loaded = loaded[id] else { return true }
            return now.timeIntervalSince(loaded.date) > staleAfter
        }
        guard !due.isEmpty else { return nil }
        inFlight.formUnion(due)

        // One main-actor task per stop: each suspends in its request, so they
        // run side by side without the arrivals crossing an isolation boundary.
        let fetches = due.map { id in
            Task { [weak self, fetch] in
                let arrivals = try? await fetch(id)
                self?.finish(id, arrivals: arrivals, date: now)
            }
        }
        let task = Task {
            for fetch in fetches { await fetch.value }
        }
        loadTask = task
        return task
    }

    /// A failed fetch stores nothing, so the stop keeps what it had, or stays a
    /// plain stop row, and is due again on the next activation.
    private func finish(_ id: StopID, arrivals: [ArrivalDeparture]?, date: Date) {
        inFlight.remove(id)
        guard let arrivals, nearest.contains(where: { $0.id == id }) else { return }
        loaded[id] = Loaded(arrivals: arrivals, date: date)
        rebuildRows()
    }

    /// Also called when the bookmarks change, which changes what's excluded,
    /// and on each poll, as a countdown moves without a fetch.
    func rebuildRows() {
        let rebuilt = HomeNearbyDepartures.rows(
            stops: nearest,
            arrivals: loaded.mapValues(\.arrivals),
            excluding: excludedKeys()
        )
        guard rebuilt != rows else { return }
        rows = rebuilt
    }
}
