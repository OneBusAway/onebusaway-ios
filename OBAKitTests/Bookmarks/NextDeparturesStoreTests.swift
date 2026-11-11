//
//  NextDeparturesStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Synchronization
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// `NextDeparturesStore` decides when the Next Departures card hits the network (#1554).
struct NextDeparturesStoreTests {
    private typealias Outcome = NextDeparturesSummary.Outcome

    /// Counts fetches and answers each with the next queued outcome, repeating
    /// the last one.
    private nonisolated final class FakeFetch: Sendable {
        private let state: Mutex<(count: Int, outcomes: [Outcome])>
        private let delay: Duration

        init(_ outcomes: [Outcome], delay: Duration = .zero) {
            state = Mutex((0, outcomes))
            self.delay = delay
        }

        var count: Int { state.withLock { $0.count } }

        func callAsFunction(_ bookmarkID: UUID?) async -> Outcome {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return state.withLock { state in
                state.count += 1
                return state.outcomes.count > 1 ? state.outcomes.removeFirst() : state.outcomes[0]
            }
        }
    }

    private nonisolated final class Clock: Sendable {
        private let date = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        var now: Date { date.withLock { $0 } }
        func advance(seconds: TimeInterval) { date.withLock { $0 += seconds } }
    }

    private let bookmarkID = UUID()
    private let clock = Clock()

    private func departures(_ minutes: Double) -> Outcome {
        .departures(bookmarkName: "Library", routeShortName: "550", headsign: "Seattle", departures: [
            NextDeparturesSummary.Departure(date: clock.now.addingTimeInterval(minutes * 60), isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        ])
    }

    private func store(_ fetch: FakeFetch) -> NextDeparturesStore {
        let clock = clock
        return NextDeparturesStore(fetch: { await fetch($0) }, now: { clock.now })
    }

    /// The intent fetches, then the card shows what it fetched.
    @Test func `The card reads what the intent fetched without fetching again`() async {
        let fetch = FakeFetch([departures(5)])
        let store = store(fetch)

        let loaded = await store.load(bookmarkID: bookmarkID)
        let shown = await store.outcome(bookmarkID: bookmarkID)

        #expect(shown == loaded)
        #expect(fetch.count == 1)
    }

    /// The system re-runs the snippet to redraw it; that must not hit the network.
    @Test func `Redrawing the card does not fetch`() async {
        let fetch = FakeFetch([departures(5)])
        let store = store(fetch)

        _ = await store.outcome(bookmarkID: bookmarkID)
        _ = await store.outcome(bookmarkID: bookmarkID)
        _ = await store.outcome(bookmarkID: bookmarkID)

        #expect(fetch.count == 1, "Only the first display, with nothing stored, fetches")
    }

    @Test func `The intent always fetches fresh departures`() async {
        let fetch = FakeFetch([departures(5), departures(4)])
        let store = store(fetch)

        _ = await store.load(bookmarkID: bookmarkID)
        let second = await store.load(bookmarkID: bookmarkID)

        #expect(second == departures(4))
        #expect(fetch.count == 2)
    }

    // Outcomes are captured before the clock moves: `departures(_:)` reads it.

    @Test func `Refresh within ten seconds of a successful fetch reuses it`() async {
        let (first, second) = (departures(5), departures(4))
        let fetch = FakeFetch([first, second])
        let store = store(fetch)
        _ = await store.load(bookmarkID: bookmarkID)

        clock.advance(seconds: 9)
        let reused = await store.refresh(bookmarkID: bookmarkID)

        #expect(reused == first)
        #expect(fetch.count == 1)
    }

    @Test func `Refresh after ten seconds fetches again`() async {
        let (first, second) = (departures(5), departures(4))
        let fetch = FakeFetch([first, second])
        let store = store(fetch)
        _ = await store.load(bookmarkID: bookmarkID)

        clock.advance(seconds: 10)
        let refreshed = await store.refresh(bookmarkID: bookmarkID)

        #expect(refreshed == second)
        #expect(fetch.count == 2)
        #expect(await store.outcome(bookmarkID: bookmarkID) == second, "The card shows the refreshed departures")
    }

    /// A failure is never reused: tapping Refresh right after one retries.
    @Test func `Refresh after a failed fetch always fetches`() async {
        let recovered = departures(5)
        let fetch = FakeFetch([.loadFailed(bookmarkName: "Library"), recovered])
        let store = store(fetch)
        _ = await store.load(bookmarkID: bookmarkID)

        clock.advance(seconds: 1)
        let refreshed = await store.refresh(bookmarkID: bookmarkID)

        #expect(refreshed == recovered)
        #expect(fetch.count == 2)
    }

    /// The card must never present old times as current.
    @Test func `A failed refresh replaces the departures it would have shown`() async {
        let fetch = FakeFetch([departures(5), .loadFailed(bookmarkName: "Library")])
        let store = store(fetch)
        _ = await store.load(bookmarkID: bookmarkID)

        clock.advance(seconds: 30)
        _ = await store.refresh(bookmarkID: bookmarkID)

        #expect(await store.outcome(bookmarkID: bookmarkID) == .loadFailed(bookmarkName: "Library"))
    }

    @Test func `Fetches running at the same time for one bookmark are shared`() async {
        let fetch = FakeFetch([departures(5)], delay: .milliseconds(100))
        let store = store(fetch)

        async let first = store.load(bookmarkID: bookmarkID)
        async let second = store.refresh(bookmarkID: bookmarkID)
        let results = await [first, second]

        #expect(results == [departures(5), departures(5)])
        #expect(fetch.count == 1)
    }

    @Test func `Bookmarks do not share outcomes`() async {
        let fetch = FakeFetch([departures(5), departures(12)])
        let store = store(fetch)
        let other = UUID()

        _ = await store.load(bookmarkID: bookmarkID)
        let otherOutcome = await store.outcome(bookmarkID: other)

        #expect(otherOutcome == departures(12))
        #expect(await store.outcome(bookmarkID: bookmarkID) == departures(5))
    }

    /// "No bookmarks" has no bookmark id; the card still shows it.
    @Test func `The answer without a bookmark is stored under no id`() async {
        let fetch = FakeFetch([.noBookmarks])
        let store = store(fetch)

        _ = await store.load(bookmarkID: nil)

        #expect(await store.outcome(bookmarkID: nil) == .noBookmarks)
        #expect(fetch.count == 1)
    }
}
