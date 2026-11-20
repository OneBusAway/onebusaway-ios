//
//  NextDeparturesCardModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// What the Next Departures card shows for each outcome (#1554).
@MainActor
struct NextDeparturesCardModelTests {
    private typealias Outcome = NextDeparturesSummary.Outcome
    private typealias Departure = NextDeparturesSummary.Departure

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func departure(_ minutes: Double, isRealTime: Bool = true, status: ScheduleStatus = .onTime, deviation: Int = 0) -> Departure {
        Departure(date: now.addingTimeInterval(minutes * 60), isRealTime: isRealTime, scheduleStatus: status, deviationMinutes: deviation)
    }

    private func departures(_ list: [Departure]) -> Outcome {
        .departures(bookmarkName: "Library", routeShortName: "550", headsign: "Seattle", departures: list)
    }

    @Test func `Departures show the bookmark, route, headsign and the next three`() {
        let model = NextDeparturesCardModel(outcome: departures([departure(32), departure(5), departure(17), departure(48)]), now: now)

        #expect(model.bookmarkName == "Library")
        #expect(model.routeShortName == "550")
        #expect(model.headsign == "Seattle")
        #expect(model.rows.map(\.timeText) == ["5m", "17m", "32m"])
        #expect(model.message == nil)
        #expect(model.showsRefresh)
        if case let .departures(rows) = model.state {
            #expect(rows.count == 3)
        } else {
            Issue.record("Expected .departures state")
        }
    }

    /// The card and the dialog must agree on which departures are "next".
    @Test func `Departed vehicles are skipped and one at the stop reads NOW`() {
        let model = NextDeparturesCardModel(outcome: departures([departure(-3), departure(-0.5), departure(9)]), now: now)

        #expect(model.rows.map(\.timeText) == ["NOW", "9m"])
    }

    /// Color is never the only signal: each row says its adherence in words.
    @Test func `Each departure says whether it is live and how it runs`() {
        let model = NextDeparturesCardModel(outcome: departures([
            departure(5, status: .onTime),
            departure(9, status: .delayed, deviation: 3),
            departure(14, status: .early, deviation: -2),
            departure(20, isRealTime: false, status: .unknown)
        ]), now: now)

        #expect(model.rows.map(\.statusText) == ["on time", "3 min late", "2 min early"])
        #expect(model.rows.map(\.status.isRealTime) == [true, true, true])
    }

    @Test func `A scheduled departure says so instead of claiming it is on time`() {
        let model = NextDeparturesCardModel(outcome: departures([departure(5, isRealTime: false, status: .unknown)]), now: now)

        #expect(model.rows.first?.statusText == "schedule data")
        #expect(model.rows.first?.status.isRealTime == false)
    }

    @Test func `VoiceOver hears the time in words and the status`() {
        let model = NextDeparturesCardModel(outcome: departures([departure(5, status: .delayed, deviation: 3), departure(8, isRealTime: false, status: .unknown)]), now: now)

        #expect(model.rows.map(\.accessibilityLabel) == [
            "in 5 minutes, live tracking, 3 min late",
            "in 8 minutes, scheduled time only, no live data"
        ])
    }

    /// Every outcome without departure rows shows what the dialog says.
    @Test(arguments: [
        (NextDeparturesSummary.Outcome.noBookmarks, false),
        (NextDeparturesSummary.Outcome.noRegion, false),
        (NextDeparturesSummary.Outcome.bookmarkUnavailable, false),
        (NextDeparturesSummary.Outcome.stopUnavailable, false),
        (NextDeparturesSummary.Outcome.loadFailed(name: "Library"), true)
    ])
    func `Other outcomes show the dialog's text and offer Refresh only after a failed load`(outcome: NextDeparturesSummary.Outcome, showsRefresh: Bool) {
        let model = NextDeparturesCardModel(outcome: outcome, now: now)

        #expect(model.message == NextDeparturesSummary.text(for: outcome, now: now))
        #expect(model.rows.isEmpty)
        #expect(model.showsRefresh == showsRefresh)
    }

    @Test func `No departures still to come shows the dialog's text with Refresh`() {
        let outcome = departures([departure(-2)])
        let model = NextDeparturesCardModel(outcome: outcome, now: now)

        #expect(model.message == "No departures for Library in the next hour.")
        #expect(model.rows.isEmpty)
        #expect(model.showsRefresh)
    }

    @Test func `Track shows only for upcoming departures with Live Activities on`() {
        let upcoming = departures([departure(5)])

        #expect(NextDeparturesCardModel(outcome: upcoming, now: now, liveActivitiesEnabled: true).showsTrack)
        #expect(!NextDeparturesCardModel(outcome: upcoming, now: now, liveActivitiesEnabled: false).showsTrack)
    }

    /// Nothing to follow: departed, none scheduled, or no departures at all.
    @Test(arguments: [
        NextDeparturesSummary.Outcome.departures(bookmarkName: "Library", routeShortName: "550", headsign: "Seattle", departures: []),
        .noBookmarks,
        .noRegion,
        .bookmarkUnavailable,
        .stopUnavailable,
        .loadFailed(name: "Library")
    ])
    func `Track is hidden without a departure to follow`(outcome: NextDeparturesSummary.Outcome) {
        #expect(!NextDeparturesCardModel(outcome: outcome, now: now, liveActivitiesEnabled: true).showsTrack)
    }

    @Test func `Track is hidden when every departure has left`() {
        #expect(!NextDeparturesCardModel(outcome: departures([departure(-2)]), now: now, liveActivitiesEnabled: true).showsTrack)
    }

    @Test func `An empty schedule shows the dialog's text with Refresh`() {
        let model = NextDeparturesCardModel(outcome: departures([]), now: now)

        #expect(model.message == NextDeparturesSummary.text(for: departures([]), now: now))
        #expect(model.showsRefresh)
    }

    // MARK: - Extended State and Formatting Invariants

    @Test func `Upcoming departures calculate correct minutes countdown values`() throws {
        let upcoming = departures([departure(5), departure(12), departure(20)])
        let model = NextDeparturesCardModel(outcome: upcoming, now: now)

        #expect(model.bookmarkName == "Library")
        #expect(model.routeShortName == "550")
        #expect(model.headsign == "Seattle")
        #expect(model.showsRefresh)

        #expect(model.rows.count == 3)
        #expect(model.rows[0].timeText == "5m")
        #expect(model.rows[1].timeText == "12m")
        #expect(model.rows[2].timeText == "20m")
    }

    @Test func `Failure outcomes show refresh but hide track action`() {
        let model = NextDeparturesCardModel(outcome: .loadFailed(name: "Library"), now: now, liveActivitiesEnabled: true)
        #expect(model.showsRefresh == true)
        #expect(model.showsTrack == false)
    }

    // MARK: - Explicit State Modeling Invariants

    @Test func `Empty bookmark outcome maps to empty state with message and no refresh`() {
        let noBookmarks = NextDeparturesCardModel(outcome: .noBookmarks, now: now)
        let expectedMessage = NextDeparturesSummary.text(for: .noBookmarks, now: now)

        #expect(noBookmarks.state == .empty(message: expectedMessage))
        #expect(noBookmarks.message == expectedMessage)
        #expect(noBookmarks.rows.isEmpty)
        #expect(!noBookmarks.showsRefresh)
        #expect(!noBookmarks.showsTrack)
    }

    @Test func `No departure outcome maps to empty state with message and refresh enabled`() {
        let emptyDepartures = NextDeparturesCardModel(outcome: departures([]), now: now)
        let expectedMessage = NextDeparturesSummary.text(for: departures([]), now: now)

        #expect(emptyDepartures.state == .empty(message: expectedMessage))
        #expect(emptyDepartures.message == expectedMessage)
        #expect(emptyDepartures.rows.isEmpty)
        #expect(emptyDepartures.showsRefresh)
        #expect(!emptyDepartures.showsTrack)
    }

    @Test func `Failure outcome maps to error state with message and refresh enabled`() {
        let failure = NextDeparturesCardModel(outcome: .loadFailed(name: "Library"), now: now, liveActivitiesEnabled: true)
        let expectedError = NextDeparturesSummary.text(for: .loadFailed(name: "Library"), now: now)

        #expect(failure.state == .error(message: expectedError))
        #expect(failure.message == expectedError)
        #expect(failure.rows.isEmpty)
        #expect(failure.showsRefresh)
        #expect(!failure.showsTrack)
    }

    @Test func `Each state has exactly one visible outcome`() {
        let upcoming = departures([departure(5)])

        let models: [(NextDeparturesCardModel, String)] = [
            (NextDeparturesCardModel(outcome: .noBookmarks, now: now), "empty bookmark"),
            (NextDeparturesCardModel(outcome: departures([]), now: now), "no departure"),
            (NextDeparturesCardModel(outcome: .loadFailed(name: "Library"), now: now), "failure"),
            (NextDeparturesCardModel(outcome: upcoming, now: now), "departures")
        ]

        for (model, label) in models {
            switch model.state {
            case .empty(let msg):
                #expect(model.rows.isEmpty, "\(label): rows must be empty")
                #expect(model.message == msg, "\(label): message must match empty text")
            case .error(let msg):
                #expect(model.rows.isEmpty, "\(label): rows must be empty")
                #expect(model.message == msg, "\(label): message must match error text")
            case .departures(let rows):
                #expect(!model.rows.isEmpty, "\(label): rows must not be empty")
                #expect(model.rows == rows, "\(label): rows must match")
                #expect(model.message == nil, "\(label): message must be nil")
            }
        }
    }
}
