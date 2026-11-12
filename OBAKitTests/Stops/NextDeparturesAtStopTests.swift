//
//  NextDeparturesAtStopTests.swift
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

/// Next Departures at Stop fetching a stop's departures from the app-group
/// suite, as the intent does with no `Application`.
@Suite(.serialized)
final class NextDeparturesAtStopLoaderTests: OBATestCase {
    /// 15th Ave E & E Galer St. Route 10 leaves toward Downtown Seattle, and
    /// its Capitol Hill trips end here.
    private let galerFixture = "arrivals_and_departures_for_stop_15th-galer.json"
    private let galerStopID = "1_11370"
    /// The fixture's `currentTime`.
    private let fixtureNow = Date(timeIntervalSince1970: 1_544_032_310.6)

    override init() async throws {
        try await super.init()
        ResolvedRegionStore(userDefaults: userDefaults).write(Fixtures.pugetSoundRegion)
    }

    private var galerEntityID: String {
        StopEntityMapping.identifier(regionID: Fixtures.pugetSoundRegion.regionIdentifier, stopID: galerStopID)
    }

    private func loader(dataLoader: MockDataLoader) -> NextDeparturesLoader {
        NextDeparturesLoader(userDefaults: userDefaults, bundledRegionsFilePath: nil, apiKey: apiKey, appVersion: appVersion, dataLoader: dataLoader)
    }

    /// Answers only a request for `stopID`'s arrivals; any other URL hits
    /// `MockDataLoader`'s `fatalError`.
    private func mockArrivals(_ dataLoader: MockDataLoader, stopID: String, file: String, statusCode: Int = 200) {
        let data = statusCode == 200 ? Fixtures.loadData(file: file) : Data("{}".utf8)
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.hasSuffix("/api/where/arrivals-and-departures-for-stop/\(stopID).json") ?? false
        }
    }

    @Test func `Asking for a stop fetches that stop and speaks its next departures`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: galerStopID, file: galerFixture)

        let outcome = await loader(dataLoader: dataLoader).outcome(stopEntityID: galerEntityID)

        // The Capitol Hill trips end at this stop, so nobody can board them.
        #expect(
            NextDeparturesSummary.text(for: outcome, now: fixtureNow)
                == "Next at 15th Ave E & E Galer St: 10 to Downtown Seattle in 6 minutes and 10 to Downtown Seattle in 21 minutes."
        )
    }

    @Test func `A stop with nothing coming says so by name`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: "1_TEST", file: "arrivals_and_departures_empty.json")
        let entityID = StopEntityMapping.identifier(regionID: Fixtures.pugetSoundRegion.regionIdentifier, stopID: "1_TEST")

        let outcome = await loader(dataLoader: dataLoader).outcome(stopEntityID: entityID)

        #expect(outcome == .stopDepartures(stopName: "Test Stop", departures: []))
        #expect(NextDeparturesSummary.text(for: outcome, now: fixtureNow) == "No departures for Test Stop in the next hour.")
    }

    @Test func `A server error is a load failure, not an empty schedule`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: galerStopID, file: galerFixture, statusCode: 500)

        let outcome = await loader(dataLoader: dataLoader).outcome(stopEntityID: galerEntityID)

        // The app has no copy of this stop, so it's named as its entity is titled.
        #expect(outcome == .loadFailed(name: "Stop 1_11370"))
    }

    @Test func `No resolved region asks the user to choose one`() async {
        ResolvedRegionStore(userDefaults: userDefaults).write(nil)

        let outcome = await loader(dataLoader: MockDataLoader(testName: name)).outcome(stopEntityID: galerEntityID)

        #expect(outcome == .noRegion)
    }

    @Test func `A stop from another region is unavailable`() async {
        let tampaStop = StopEntityMapping.identifier(regionID: Fixtures.tampaRegion.regionIdentifier, stopID: galerStopID)

        let outcome = await loader(dataLoader: MockDataLoader(testName: name)).outcome(stopEntityID: tampaStop)

        #expect(outcome == .stopUnavailable)
    }

    /// The rider's "Show Departures" choice is read from the suite, as the app saves it.
    @Test func `The saved departure filter applies to the answer`() async throws {
        userDefaults.set(ArrivalDepartureFilter.scheduledOnly.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: galerStopID, file: galerFixture)

        let outcome = await loader(dataLoader: dataLoader).outcome(stopEntityID: galerEntityID)

        #expect(outcome == .stopDepartures(stopName: "15th Ave E & E Galer St", departures: []), "Every fixture departure is real-time")
    }

    /// With nothing saved, the white-label default applies.
    @Test func `The brand's default departure filter applies when the rider chose none`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: galerStopID, file: galerFixture)
        let loader = NextDeparturesLoader(userDefaults: userDefaults, bundledRegionsFilePath: nil, apiKey: apiKey, appVersion: appVersion, defaultArrivalDepartureFilter: .scheduledOnly, dataLoader: dataLoader)

        let outcome = await loader.outcome(stopEntityID: galerEntityID)

        #expect(outcome == .stopDepartures(stopName: "15th Ave E & E Galer St", departures: []))
    }

    @Test func `A saved filter that isn't valid falls back to the brand default`() {
        #expect(ArrivalDepartureFilter.effective(in: userDefaults, brandDefault: .estimatedOnly) == .estimatedOnly)

        userDefaults.set("garbage", forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter.effective(in: userDefaults, brandDefault: .estimatedOnly) == .estimatedOnly)

        userDefaults.set(ArrivalDepartureFilter.all.rawValue, forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey)
        #expect(ArrivalDepartureFilter.effective(in: userDefaults, brandDefault: .estimatedOnly) == .all)
    }

    /// Hidden routes are read from the stop's saved preferences. E John St &
    /// 15th Ave E serves routes 8, 10 and 43; the fixture has an 8 and two 43s.
    @Test func `A route hidden at the stop is left out`() async throws {
        let fixture = "arrivals_and_departures_for_stop_1_29261.json"
        let stop = try #require(try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixture).stop)
        UserDefaultsStore(userDefaults: userDefaults).set(
            stopPreferences: StopPreferences(sortType: .time, hiddenRoutes: ["1_43"]),
            stop: stop,
            region: Fixtures.pugetSoundRegion
        )
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, stopID: "1_29261", file: fixture)
        let entityID = StopEntityMapping.identifier(regionID: Fixtures.pugetSoundRegion.regionIdentifier, stopID: "1_29261")

        let outcome = await loader(dataLoader: dataLoader).outcome(stopEntityID: entityID)

        guard case let .stopDepartures(_, departures) = outcome else {
            Issue.record("Expected departures, got \(outcome)")
            return
        }
        #expect(departures.map(\.routeShortName) == ["8"])
    }

    /// The stop page's filters apply, so Siri doesn't read out what the rider hid.
    @Test func `The rider's departure filter and hidden routes apply`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: galerFixture).arrivalsAndDepartures
        let route10 = "1_100002"
        let hidden = StopPreferences(sortType: .time, hiddenRoutes: [route10])

        let all = NextDeparturesLoader.boardable(arrivals, filter: .all, preferences: StopPreferences(), stopRouteIDs: [route10])
        #expect(all.map(\.tripHeadsign) == ["Downtown Seattle", "Downtown Seattle"])

        let scheduledOnly = NextDeparturesLoader.boardable(arrivals, filter: .scheduledOnly, preferences: StopPreferences(), stopRouteIDs: [route10])
        #expect(scheduledOnly.isEmpty, "Every fixture departure is real-time")

        let routeHidden = NextDeparturesLoader.boardable(arrivals, filter: .all, preferences: hidden, stopRouteIDs: [route10, "1_other"])
        #expect(routeHidden.isEmpty)

        // As on the stop page: with every route hidden, the hiding is dropped.
        let everyRouteHidden = NextDeparturesLoader.boardable(arrivals, filter: .all, preferences: hidden, stopRouteIDs: [route10])
        #expect(everyRouteHidden.count == 2)
    }
}

/// What Next Departures at Stop says and shows, and how its card is cached.
@MainActor
struct NextDeparturesAtStopTests {
    /// The keys a store fetched, in order.
    private nonisolated final class FetchedKeys: Sendable {
        private let state = Mutex([NextDeparturesCardKey]())
        var keys: [NextDeparturesCardKey] { state.withLock { $0 } }
        func append(_ key: NextDeparturesCardKey) { state.withLock { $0.append(key) } }
    }

    private typealias Outcome = NextDeparturesSummary.Outcome
    private typealias StopDeparture = NextDeparturesSummary.StopDeparture

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let stopEntityID = StopEntityMapping.identifier(regionID: 1, stopID: "1_75403")

    private func departure(_ route: String, _ headsign: String?, _ minutes: Double) -> StopDeparture {
        StopDeparture(
            routeShortName: route,
            headsign: headsign,
            departure: NextDeparturesSummary.Departure(date: now.addingTimeInterval(minutes * 60), isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        )
    }

    private var pine: Outcome {
        .stopDepartures(stopName: "3rd Ave & Pine St", departures: [
            departure("49", "Capitol Hill", 12),
            departure("8", "Downtown", 4),
            departure("C Line", nil, 30),
            departure("10", "Volunteer Park", -2),
            departure("E Line", "Aurora Village", 45)
        ])
    }

    @Test func `The answer lists the next three departures across routes`() {
        #expect(
            NextDeparturesSummary.text(for: pine, now: now)
                == "Next at 3rd Ave & Pine St: 8 to Downtown in 4 minutes, 49 to Capitol Hill in 12 minutes, and C Line in 30 minutes."
        )
    }

    @Test func `A stop in another region gets its own answer`() {
        #expect(NextDeparturesSummary.text(for: .stopUnavailable, now: now) == "That stop isn't in your current region.")
    }

    @Test func `The card names the stop and gives each row its route and headsign`() {
        let model = NextDeparturesCardModel(outcome: pine, now: now, liveActivitiesEnabled: true)

        #expect(model.stopName == "3rd Ave & Pine St")
        #expect(model.bookmarkName == nil)
        #expect(model.rows.map(\.routeShortName) == ["8", "49", "C Line"])
        #expect(model.rows.map(\.headsign) == ["Downtown", "Capitol Hill", nil])
        #expect(model.rows.map(\.timeText) == ["4m", "12m", "30m"])
        #expect(model.rows.first?.accessibilityLabel == "8 to Downtown in 4 minutes, live tracking, on time")
        #expect(model.message == nil)
        #expect(model.showsRefresh)
        #expect(!model.showsTrack, "A stop has no bookmark to track")
    }

    @Test func `A stop card with nothing coming shows the spoken sentence and Refresh`() {
        let model = NextDeparturesCardModel(outcome: .stopDepartures(stopName: "3rd Ave & Pine St", departures: [departure("8", "Downtown", -3)]), now: now)

        #expect(model.rows.isEmpty)
        #expect(model.message == "No departures for 3rd Ave & Pine St in the next hour.")
        #expect(model.showsRefresh)
    }

    @Test func `Card intents carry a stop entity id as a stop`() {
        #expect(NextDeparturesCardKey(stopEntityID) == .stop(stopEntityID))
        #expect(NextDeparturesCardKey("region_1_stop_") == .invalid)
    }

    /// The card reads the intent's outcome for that stop, and stops don't share one.
    @Test func `The store keeps one outcome per stop`() async {
        let fetched = FetchedKeys()
        let store = NextDeparturesStore(fetch: { key in
            fetched.append(key)
            if case .stop(let id) = key { return .stopDepartures(stopName: id, departures: []) }
            return .noRegion
        })
        let other = StopEntityMapping.identifier(regionID: 1, stopID: "1_11370")

        _ = await store.load(.stop(stopEntityID))
        let shown = await store.outcome(.stop(stopEntityID))
        let otherShown = await store.outcome(.stop(other))

        #expect(shown == .stopDepartures(stopName: stopEntityID, departures: []))
        #expect(otherShown == .stopDepartures(stopName: other, departures: []))
        #expect(fetched.keys == [.stop(stopEntityID), .stop(other)])
    }

    /// A stop card's Refresh tap reuses a fetch younger than ten seconds, as a bookmark's does.
    @Test func `Refresh on a stop card reuses a recent fetch`() async {
        let fetched = FetchedKeys()
        let store = NextDeparturesStore(fetch: { key in
            fetched.append(key)
            return .stopDepartures(stopName: "Pine", departures: [])
        })

        _ = await store.load(.stop(stopEntityID))
        _ = await store.refresh(.stop(stopEntityID))

        #expect(fetched.keys == [.stop(stopEntityID)])
    }

    @Test func `Refresh fetches for a stop or a bookmark only`() {
        #expect(NextDeparturesCardKey(stopEntityID).isRefreshable)
        #expect(NextDeparturesCardKey(UUID().uuidString).isRefreshable)
        #expect(!NextDeparturesCardKey("").isRefreshable)
        #expect(!NextDeparturesCardKey("garbage").isRefreshable)
    }

    /// Without a stop, Siri asks for one rather than the intent guessing.
    @Test func `Without a stop the intent asks for one`() async {
        await #expect(throws: (any Error).self) {
            _ = try await NextDeparturesAtStopIntent().perform()
        }
    }
}
