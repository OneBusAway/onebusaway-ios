//
//  NextDeparturesStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The latest Next Departures outcome for each bookmark or stop, shared by the
/// intents that fetch it and the card that shows it (#1554).
///
/// The system may re-run the card's snippet intent at any time, to redraw it,
/// so the snippet only reads from here, and fetches only when there is nothing
/// to read (a fresh process). `NextDeparturesIntent` and
/// `NextDeparturesAtStopIntent` fetch on every run;
/// `RefreshNextDeparturesIntent` fetches unless a successful fetch is younger
/// than `refreshReuseInterval`. Kept in memory: it lives as long as the process
/// the system runs the intents in, which is all the card needs.
///
/// Keyed by what the card is about: a bookmark, a stop, or `noBookmark`, the
/// request with no bookmark parameter that found no trip bookmark to answer
/// for (`noBookmarks`, `noRegion`), so the card can show those answers too.
actor NextDeparturesStore {
    typealias Outcome = NextDeparturesSummary.Outcome
    typealias Key = NextDeparturesCardKey

    /// Fetches the outcome for a key.
    typealias Fetch = @Sendable (Key) async -> Outcome

    static let shared = NextDeparturesStore()

    /// Refresh taps this soon after a successful fetch reuse it instead of
    /// fetching again, so tapping Refresh repeatedly can't flood the server.
    static let refreshReuseInterval: TimeInterval = 10

    private struct Entry {
        let outcome: Outcome
        let fetchedAt: Date
    }

    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Outcome, Never>] = [:]

    init(fetch: @escaping Fetch = { await NextDeparturesStore.fetchFromApp($0) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.now = now
    }

    /// Fetches, stores and returns the outcome. For the Next Departures
    /// intents, which always answer with fresh departures.
    func load(_ key: Key) async -> Outcome {
        await fetchAndStore(key)
    }

    /// The stored outcome, fetching only if there is none. For the card's
    /// snippet intent, which the system may re-run whenever it redraws.
    func outcome(_ key: Key) async -> Outcome {
        if let entry = entries[key] {
            return entry.outcome
        }
        return await fetchAndStore(key)
    }

    /// Fetches again unless a successful fetch is younger than
    /// `refreshReuseInterval`. A failed fetch is never reused, and replaces the
    /// stored outcome, so the card never shows old departures as current.
    func refresh(_ key: Key) async -> Outcome {
        if let entry = entries[key],
           entry.outcome.isFetchedDepartures,
           now().timeIntervalSince(entry.fetchedAt) < Self.refreshReuseInterval {
            return entry.outcome
        }
        return await fetchAndStore(key)
    }

    /// Joins a fetch already running for the same key rather than starting a
    /// second one, then records the result.
    private func fetchAndStore(_ key: Key) async -> Outcome {
        if let running = inFlight[key] {
            return await running.value
        }

        let task = Task { [fetch] in await fetch(key) }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        entries[key] = Entry(outcome: outcome, fetchedAt: now())
        return outcome
    }

    /// Reads the bookmarks, stops, region and API key the app shares through
    /// its app group, as the widget does; intents can't reach `Application`.
    @MainActor
    static func fetchFromApp(_ key: Key) async -> Outcome {
        guard let loader = NextDeparturesLoader(bundle: .main) else {
            Logger.error("Next Departures Shortcut: app group UserDefaults unavailable.")
            return .noRegion
        }

        switch key {
        case .bookmark(let bookmarkID):
            return await loader.outcome(bookmarkID: bookmarkID)
        case .stop(let stopEntityID):
            return await loader.outcome(stopEntityID: stopEntityID)
        case .invalid:
            return .bookmarkUnavailable
        case .noBookmark:
            break
        }

        // No bookmark parameter. The intent only gets here when there was no
        // trip bookmark to answer for, but bookmarks may have changed since.
        let candidates = (try? await BookmarkEntityQuery().suggestedEntities()) ?? []
        switch candidates.count {
        case 0:
            return .noBookmarks
        case 1:
            return await loader.outcome(bookmarkID: candidates[0].id)
        default:
            return .bookmarkUnavailable
        }
    }
}

extension NextDeparturesSummary.Outcome {
    /// Whether this is a successful fetch of departures, the only outcome a
    /// Refresh may reuse. An empty list counts: the fetch worked.
    nonisolated var isFetchedDepartures: Bool {
        switch self {
        case .departures, .stopDepartures: return true
        case .noBookmarks, .noRegion, .bookmarkUnavailable, .stopUnavailable, .loadFailed: return false
        }
    }
}
