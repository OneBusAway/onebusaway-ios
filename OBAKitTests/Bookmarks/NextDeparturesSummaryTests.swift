//
//  NextDeparturesSummaryTests.swift
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

@MainActor
@Suite(.serialized)
final class NextDeparturesSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutesFromNow(_ minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    private func departure(_ minutes: Double, isRealTime: Bool = true) -> NextDeparturesSummary.Departure {
        NextDeparturesSummary.Departure(date: minutesFromNow(minutes), isRealTime: isRealTime, scheduleStatus: .onTime, deviationMinutes: 0)
    }

    @Test func `Zero minutes reads as now`() {
        #expect(NextDeparturesSummary.relativeTime(minutes: 0) == "now")
    }

    @Test func `One minute is singular and more are plural`() {
        #expect(NextDeparturesSummary.relativeTime(minutes: 1) == "in 1 minute")
        #expect(NextDeparturesSummary.relativeTime(minutes: 5) == "in 5 minutes")
    }

    /// Partial minutes truncate, as on the stop page: 5m50s still says 5.
    @Test func `Sentence names the route and lists the next three departures`() {
        let sentence = NextDeparturesSummary.departuresSentence(
            routeShortName: "550",
            headsign: "Seattle",
            dates: [minutesFromNow(32), minutesFromNow(5 + 50.0 / 60), minutesFromNow(17), minutesFromNow(48)],
            now: now
        )

        #expect(sentence == "550 to Seattle departs in 5 minutes. Then in 17 minutes and in 32 minutes.")
    }

    @Test func `A single departure has no then clause`() {
        let sentence = NextDeparturesSummary.departuresSentence(routeShortName: "550", headsign: "Seattle", dates: [minutesFromNow(1)], now: now)

        #expect(sentence == "550 to Seattle departs in 1 minute.")
    }

    /// Trip-bookmark arrivals are not filtered for the past upstream, so the
    /// summary must drop a bus that already left rather than report it.
    @Test func `Departed vehicles are skipped and the one at the stop is now`() {
        let sentence = NextDeparturesSummary.departuresSentence(
            routeShortName: "550",
            headsign: "Seattle",
            dates: [minutesFromNow(-3), minutesFromNow(-0.5), minutesFromNow(9)],
            now: now
        )

        #expect(sentence == "550 to Seattle departs now. Then in 9 minutes.")
    }

    @Test func `No upcoming departures names the bookmark`() {
        let outcome = NextDeparturesSummary.Outcome.departures(bookmarkName: "Library", routeShortName: "550", headsign: "Seattle", departures: [departure(-2)])

        #expect(NextDeparturesSummary.departuresSentence(routeShortName: "550", headsign: "Seattle", dates: [], now: now) == nil)
        #expect(NextDeparturesSummary.text(for: outcome, now: now) == "No departures for Library in the next hour.")
    }

    @Test func `Each failure has its own message`() {
        let messages = [
            NextDeparturesSummary.text(for: .noBookmarks, now: now),
            NextDeparturesSummary.text(for: .noRegion, now: now),
            NextDeparturesSummary.text(for: .bookmarkUnavailable, now: now),
            NextDeparturesSummary.text(for: .loadFailed(bookmarkName: "Library"), now: now)
        ]

        #expect(Set(messages).count == messages.count)
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(messages[3] == "Couldn't load departures for Library. Check your connection and try again.")
    }

    /// The card needs per-departure status, but what Siri says must not change.
    @Test func `Text for departures is the sentence from their dates`() {
        let departures = [departure(32), departure(5, isRealTime: false), departure(17)]
        let outcome = NextDeparturesSummary.Outcome.departures(bookmarkName: "Library", routeShortName: "550", headsign: "Seattle", departures: departures)

        #expect(NextDeparturesSummary.text(for: outcome, now: now) == "550 to Seattle departs in 5 minutes. Then in 17 minutes and in 32 minutes.")
    }
}

@Suite(.serialized)
final class NextDeparturesLoaderTests: OBATestCase {
    private let galerFixture = "arrivals_and_departures_for_stop_15th-galer.json"
    private let capitolHill = "Capitol Hill Via 15th Ave E"

    override init() async throws {
        try await super.init()
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
    }

    private func loader(dataLoader: MockDataLoader) -> NextDeparturesLoader {
        NextDeparturesLoader(userDefaults: userDefaults, bundledRegionsFilePath: nil, apiKey: apiKey, appVersion: appVersion, dataLoader: dataLoader)
    }

    private func addCapitolHillBookmark(regionIdentifier: Int? = nil) throws -> Bookmark {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: galerFixture).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first { $0.tripHeadsign == capitolHill })
        let bookmark = Bookmark(
            name: "10 to Capitol Hill",
            regionIdentifier: regionIdentifier ?? Fixtures.pugetSoundRegion.regionIdentifier,
            arrivalDeparture: arrivalDeparture
        )
        UserDefaultsStore(userDefaults: userDefaults).add(bookmark)
        return bookmark
    }

    private func mockArrivals(_ dataLoader: MockDataLoader, statusCode: Int = 200) {
        let data = statusCode == 200 ? Fixtures.loadData(file: galerFixture) : Data("{}".utf8)
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }
    }

    /// The stop also serves route 10 toward Downtown; a trip bookmark must
    /// only hear about its own headsign.
    @Test func `Only the bookmarked route and headsign are reported`() async throws {
        let bookmark = try addCapitolHillBookmark()
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader)

        let outcome = await loader(dataLoader: dataLoader).outcome(bookmarkID: bookmark.id)

        guard case let .departures(bookmarkName, route, headsign, departures) = outcome else {
            Issue.record("Expected departures, got \(outcome)")
            return
        }
        #expect(bookmarkName == "10 to Capitol Hill")
        #expect(route == "10")
        #expect(headsign == capitolHill)
        #expect(departures.count == 3)
    }

    /// Each departure keeps the live/scheduled flag and the deviation from its
    /// `ArrivalDeparture`, which the card's status label is built from.
    @Test func `Departures carry live status and deviation from the arrivals`() async throws {
        let bookmark = try addCapitolHillBookmark()
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader)
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: galerFixture).arrivalsAndDepartures
            .filter { $0.tripHeadsign == capitolHill }
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }

        let outcome = await loader(dataLoader: dataLoader).outcome(bookmarkID: bookmark.id)

        guard case let .departures(_, _, _, departures) = outcome else {
            Issue.record("Expected departures, got \(outcome)")
            return
        }
        #expect(departures == arrivals.map(NextDeparturesSummary.Departure.init(arrivalDeparture:)))
    }

    @Test func `A server error is a load failure, not an empty schedule`() async throws {
        let bookmark = try addCapitolHillBookmark()
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, statusCode: 500)

        let outcome = await loader(dataLoader: dataLoader).outcome(bookmarkID: bookmark.id)

        #expect(outcome == .loadFailed(bookmarkName: "10 to Capitol Hill"))
    }

    @Test func `A bookmark from another region is unavailable`() async throws {
        let bookmark = try addCapitolHillBookmark(regionIdentifier: Fixtures.tampaRegion.regionIdentifier)

        let outcome = await loader(dataLoader: MockDataLoader(testName: name)).outcome(bookmarkID: bookmark.id)

        #expect(outcome == .bookmarkUnavailable)
    }

    @Test func `A deleted bookmark is unavailable`() async {
        let outcome = await loader(dataLoader: MockDataLoader(testName: name)).outcome(bookmarkID: UUID())

        #expect(outcome == .bookmarkUnavailable)
    }

    /// Siri waits on this fetch; URLSession's default would hang for a minute.
    @Test func `Fetches time out within ten seconds unless a loader is injected`() throws {
        let loader = NextDeparturesLoader(userDefaults: userDefaults, bundledRegionsFilePath: nil, apiKey: apiKey, appVersion: appVersion)
        let session = try #require(loader.dataLoader as? URLSession)

        #expect(session.configuration.timeoutIntervalForRequest <= 10)
        #expect(session.configuration.timeoutIntervalForResource <= 10)

        let injected = MockDataLoader(testName: name)
        #expect(self.loader(dataLoader: injected).dataLoader as? MockDataLoader === injected)
    }

    @Test func `No resolved region asks the user to choose one`() async throws {
        let bookmark = try addCapitolHillBookmark()
        ResolvedRegionStore(userDefaults: userDefaults).write(nil)

        let outcome = await loader(dataLoader: MockDataLoader(testName: name)).outcome(bookmarkID: bookmark.id)

        #expect(outcome == .noRegion)
    }
}
