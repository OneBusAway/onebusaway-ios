//
//  NearbyRoutesModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct NearbyRoutesModelTests {

    @MainActor
    private final class TestState {
        var fetchCount = 0
        var isLowPower = false
        var isOffline = false

        func recordFetch() {
            fetchCount += 1
        }
    }

    private let seattleFix = CLLocation(latitude: 47.6097, longitude: -122.3378)

    private func makeAPIService() -> RESTAPIService {
        RESTAPIService.standalone(region: Fixtures.pugetSoundRegion, apiKey: "key", appVersion: "1.0", uuid: "uuid")
    }

    private func makeDirection(routeID: String = "1_10", headsign: String = "Downtown") throws -> NearbyRouteDirection {
        let route = try Fixtures.createRoute(id: routeID)
        let stop = Stop(id: "1_100", name: "15th & Galer", direction: "S", location: seattleFix)
        let arrival: ArrivalDeparture = try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
        let directionStop = RouteDirectionStop(stop: stop, distance: 50, departures: [arrival])
        let key = RouteDirectionKey(routeID: routeID, direction: headsign)
        return NearbyRouteDirection(key: key, route: route, headsign: headsign, stops: [directionStop])
    }

    @Test @MainActor func `Initial phase is locating`() {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        #expect(model.phase == .locating)
        #expect(!model.isPolling)
    }

    @Test @MainActor func `Not determined authorization requests authorization`() async {
        var requestedAuth = false
        let model = NearbyRoutesModel(
            authorizationProvider: { .notDetermined },
            requestAuthorization: { requestedAuth = true },
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .awaitingAuthorization)
        #expect(requestedAuth)
    }

    @Test @MainActor func `Denied authorization sets locationDenied without location request`() async {
        var requestedLocation = false
        let model = NearbyRoutesModel(
            authorizationProvider: { .denied },
            requestAuthorization: {},
            locationRequester: {
                requestedLocation = true
                return self.seattleFix
            },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .locationDenied)
        #expect(!requestedLocation)
    }

    @Test @MainActor func `LocationServiceError sets locationDenied`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { throw LocationServiceError.notAuthorized },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .locationDenied)
    }

    @Test @MainActor func `Generic location failure sets failed phase`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { throw NSError(domain: "test", code: -1) },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        if case .failed(let message) = model.phase {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected failed phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Missing region transitions to noRegion`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { false },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .noRegion)
    }

    @Test @MainActor func `Missing API service transitions to noRegion`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .noRegion)
    }

    @Test @MainActor func `Successful fetch with directions transitions to loaded`() async throws {
        let direction = try makeDirection()
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in [direction] }
        )

        await model.performRefresh()

        if case .loaded(let directions) = model.phase {
            #expect(directions.count == 1)
            #expect(directions.first?.headsign == "Downtown")
            #expect(model.origin == self.seattleFix)
            #expect(model.loadedAt != nil)
        } else {
            Issue.record("Expected loaded phase, got \(model.phase)")
        }
    }

    @Test @MainActor func `Successful fetch with empty directions transitions to empty`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in [] }
        )

        await model.performRefresh()

        #expect(model.phase == .empty)
    }

    @Test @MainActor func `Active cadence polls again after activeInterval`() async {
        let clock = TestClock()
        let state = TestState()
        let policy = NearbyPollingCadencePolicy(activeInterval: .seconds(60), lowPowerInterval: .seconds(180), offlineInterval: .seconds(60))

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                return []
            },
            cadencePolicy: policy,
            powerStateProvider: { state.isLowPower },
            clock: clock
        )

        model.startPolling()
        #expect(model.isPolling)

        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        // Advance by less than activeInterval -> no new poll
        clock.advance(by: .seconds(30))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 1)

        // Advance to full 60s -> poll 2 happens
        clock.advance(by: .seconds(30))
        await poll(until: { state.fetchCount == 2 })

        model.stopPolling()
    }

    @Test @MainActor func `Low power cadence sleeps for lowPowerInterval`() async {
        let clock = TestClock()
        let state = TestState()
        state.isLowPower = true
        let policy = NearbyPollingCadencePolicy(activeInterval: .seconds(60), lowPowerInterval: .seconds(180), offlineInterval: .seconds(60))

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                return []
            },
            cadencePolicy: policy,
            powerStateProvider: { state.isLowPower },
            clock: clock
        )

        model.startPolling()

        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        // Advance by normal active interval (60s) -> should NOT poll yet in low power mode!
        clock.advance(by: .seconds(60))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 1)

        // Advance remaining 120s to reach 180s -> poll 2 executes
        clock.advance(by: .seconds(120))
        await poll(until: { state.fetchCount == 2 })

        model.stopPolling()
    }

    @Test @MainActor func `Cancellation stops polling and cancels sleepers`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                return []
            },
            clock: clock
        )

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        model.stopPolling()
        #expect(!model.isPolling)

        await poll(until: { clock.sleeperCount == 0 })

        // Advancing clock does not trigger any further polls
        clock.advance(by: .seconds(120))
        await Task.yield()
        #expect(state.fetchCount == 1)
        #expect(clock.sleeperCount == 0)
    }

    @Test @MainActor func `No-network fallback switches cadence to offline interval`() async {
        let clock = TestClock()
        let state = TestState()
        state.isOffline = true
        let policy = NearbyPollingCadencePolicy(activeInterval: .seconds(60), lowPowerInterval: .seconds(300), offlineInterval: .seconds(45))

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                if state.isOffline {
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
                }
                return []
            },
            cadencePolicy: policy,
            powerStateProvider: { false },
            clock: clock
        )

        model.startPolling()

        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        // When offline, interval is 45s
        clock.advance(by: .seconds(30))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 1)

        // Advance 15s to reach 45s offlineInterval -> retry triggers
        state.isOffline = false
        clock.advance(by: .seconds(15))
        await poll(until: { state.fetchCount == 2 })

        // Now that it succeeded, interval returns to activeInterval (60s)
        await poll(until: { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(45))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 2)

        clock.advance(by: .seconds(15))
        await poll(until: { state.fetchCount == 3 })

        model.stopPolling()
    }

    @Test @MainActor func `Inactive screen owns no unnecessary poll`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                return []
            },
            clock: clock
        )

        // Without calling startPolling(), time advancing executes 0 polls
        clock.advance(by: .seconds(300))
        #expect(state.fetchCount == 0)
        #expect(!model.isPolling)
    }

    @Test @MainActor func `Manual refresh restarts cadence from new tick`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                return []
            },
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60)),
            clock: clock
        )

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        // Partial time passes (30s)
        clock.advance(by: .seconds(30))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 1)

        // User taps manual refresh:
        model.refresh()
        await poll(until: { state.fetchCount == 2 })
        await poll(until: { clock.sleeperCount == 1 })

        // Another 30s passes -> should NOT tick yet because timer was reset to 60s!
        clock.advance(by: .seconds(30))
        #expect(clock.sleeperCount == 1)
        await Task.yield()
        #expect(state.fetchCount == 2)

        // 30s more (total 60s after refresh) -> tick 3!
        clock.advance(by: .seconds(30))
        await poll(until: { state.fetchCount == 3 })

        model.stopPolling()
    }
}
