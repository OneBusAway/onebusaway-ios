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

/// The latest Next Departures outcome for each bookmark, shared by the intents
/// that fetch it and the card that shows it (#1554).
///
/// The system may re-run the card's snippet intent at any time, to redraw it,
/// so the snippet only reads from here, and fetches only when there is nothing
/// to read (a fresh process). `NextDeparturesIntent` fetches on every run;
/// `RefreshNextDeparturesIntent` fetches unless a successful fetch is younger
/// than `refreshReuseInterval`. Kept in memory: it lives as long as the process
/// the system runs the intents in, which is all the card needs.
///
/// Keyed by bookmark id. `nil` is the request with no bookmark parameter that
/// found no trip bookmark to answer for (`noBookmarks`, `noRegion`), so the
/// card can show those answers too.
actor NextDeparturesStore {
    typealias Outcome = NextDeparturesSummary.Outcome

    /// Fetches the outcome for a bookmark id, or for "no bookmark" with `nil`.
    typealias Fetch = @Sendable (UUID?) async -> Outcome

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
    private var entries: [UUID?: Entry] = [:]
    private var inFlight: [UUID?: Task<Outcome, Never>] = [:]

    init(fetch: @escaping Fetch = { await NextDeparturesStore.fetchFromApp($0) }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetch = fetch
        self.now = now
    }

    /// Fetches, stores and returns the outcome. For `NextDeparturesIntent`,
    /// which always answers with fresh departures.
    func load(bookmarkID: UUID?) async -> Outcome {
        await fetchAndStore(bookmarkID)
    }

    /// The stored outcome, fetching only if there is none. For the card's
    /// snippet intent, which the system may re-run whenever it redraws.
    func outcome(bookmarkID: UUID?) async -> Outcome {
        if let entry = entries[bookmarkID] {
            return entry.outcome
        }
        return await fetchAndStore(bookmarkID)
    }

    /// Fetches again unless a successful fetch is younger than
    /// `refreshReuseInterval`. A failed fetch is never reused, and replaces the
    /// stored outcome, so the card never shows old departures as current.
    func refresh(bookmarkID: UUID?) async -> Outcome {
        if let entry = entries[bookmarkID],
           entry.outcome.isFetchedDepartures,
           now().timeIntervalSince(entry.fetchedAt) < Self.refreshReuseInterval {
            return entry.outcome
        }
        return await fetchAndStore(bookmarkID)
    }

    /// Joins a fetch already running for the same key rather than starting a
    /// second one, then records the result.
    private func fetchAndStore(_ bookmarkID: UUID?) async -> Outcome {
        if let running = inFlight[bookmarkID] {
            return await running.value
        }

        let task = Task { [fetch] in await fetch(bookmarkID) }
        inFlight[bookmarkID] = task
        let outcome = await task.value
        inFlight[bookmarkID] = nil
        entries[bookmarkID] = Entry(outcome: outcome, fetchedAt: now())
        return outcome
    }

    /// Reads the bookmarks, region and API key the app shares through its app
    /// group, as the widget does; intents can't reach `Application`.
    @MainActor
    static func fetchFromApp(_ bookmarkID: UUID?) async -> Outcome {
        guard let loader = NextDeparturesLoader(bundle: .main) else {
            Logger.error("Next Departures Shortcut: app group UserDefaults unavailable.")
            return .noRegion
        }

        if let bookmarkID {
            return await loader.outcome(bookmarkID: bookmarkID)
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
        if case .departures = self { return true }
        return false
    }
}
