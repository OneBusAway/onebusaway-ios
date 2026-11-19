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
        weak var model: NearbyRoutesModel?
        var phasesAtLocate: [NearbyRoutesModel.Phase] = []
        var phasesAtLoad: [NearbyRoutesModel.Phase] = []

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

    @Test @MainActor func `Offline directions failure shows the offline message`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            }
        )

        await model.performRefresh()

        #expect(model.phase == .failed(Strings.nearbyOffline))
    }

    @Test @MainActor func `Non-offline directions failure shows the error description`() async {
        let error = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Server exploded"])
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in throw error }
        )

        await model.performRefresh()

        #expect(model.phase == .failed("Server exploded"))
    }

    @Test @MainActor func `Background poll keeps the empty screen instead of showing progress`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                if let phase = state.model?.phase { state.phasesAtLocate.append(phase) }
                return self.seattleFix
            },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                if let phase = state.model?.phase { state.phasesAtLoad.append(phase) }
                state.recordFetch()
                return []
            },
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60)),
            clock: clock
        )
        state.model = model

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })
        #expect(model.phase == .empty)

        clock.advance(by: .seconds(60))
        await poll(until: { state.fetchCount == 2 })

        // The first pass shows progress; the background poll keeps the empty screen.
        #expect(state.phasesAtLocate == [.locating, .empty])
        #expect(state.phasesAtLoad == [.loading, .empty])
        #expect(model.phase == .empty)

        model.stopPolling()
    }

    @Test @MainActor func `Background poll keeps the failed screen instead of showing progress`() async {
        let clock = TestClock()
        let state = TestState()
        let error = NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Server exploded"])

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                if let phase = state.model?.phase { state.phasesAtLocate.append(phase) }
                return self.seattleFix
            },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                state.recordFetch()
                throw error
            },
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60)),
            clock: clock
        )
        state.model = model

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        clock.advance(by: .seconds(60))
        await poll(until: { state.fetchCount == 2 })

        #expect(state.phasesAtLocate == [.locating, .failed("Server exploded")])
        #expect(model.phase == .failed("Server exploded"))

        model.stopPolling()
    }

    @Test @MainActor func `Background poll keeps the no-region screen instead of showing progress`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                if let phase = state.model?.phase { state.phasesAtLocate.append(phase) }
                state.recordFetch()
                return self.seattleFix
            },
            hasRegion: { false },
            apiServiceProvider: { nil },
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60)),
            clock: clock
        )
        state.model = model

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        clock.advance(by: .seconds(60))
        await poll(until: { state.fetchCount == 2 })

        #expect(state.phasesAtLocate == [.locating, .noRegion])
        #expect(model.phase == .noRegion)

        model.stopPolling()
    }

    @Test @MainActor func `Manual refresh shows progress over the empty screen`() async {
        let clock = TestClock()
        let state = TestState()

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                if let phase = state.model?.phase { state.phasesAtLocate.append(phase) }
                return self.seattleFix
            },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                if let phase = state.model?.phase { state.phasesAtLoad.append(phase) }
                state.recordFetch()
                return []
            },
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60)),
            clock: clock
        )
        state.model = model

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        model.refresh()
        await poll(until: { state.fetchCount == 2 })

        #expect(state.phasesAtLocate == [.locating, .locating])
        #expect(state.phasesAtLoad == [.loading, .loading])

        model.stopPolling()
    }

    @Test @MainActor func `Turning off Low Power Mode shortens the running sleep`() async {
        let clock = TestClock()
        let state = TestState()
        state.isLowPower = true
        let center = NotificationCenter()

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
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60), lowPowerInterval: .seconds(180)),
            powerStateProvider: { state.isLowPower },
            clock: clock,
            notificationCenter: center
        )

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        // 30s into the 180s low-power sleep, Low Power Mode turns off: the
        // sleep now ends 60s after it began, not 180s.
        clock.advance(by: .seconds(30))
        state.isLowPower = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await poll(until: { clock.sleeperCount == 1 })
        await Task.yield()
        #expect(state.fetchCount == 1)

        clock.advance(by: .seconds(30))
        await poll(until: { state.fetchCount == 2 })

        model.stopPolling()
    }

    @Test @MainActor func `Turning off Low Power Mode past the active interval polls right away`() async {
        let clock = TestClock()
        let state = TestState()
        state.isLowPower = true
        let center = NotificationCenter()

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
            cadencePolicy: NearbyPollingCadencePolicy(activeInterval: .seconds(60), lowPowerInterval: .seconds(180)),
            powerStateProvider: { state.isLowPower },
            clock: clock,
            notificationCenter: center
        )

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        clock.advance(by: .seconds(90))
        #expect(state.fetchCount == 1)
        state.isLowPower = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await poll(until: { state.fetchCount == 2 })

        model.stopPolling()
    }

    @Test @MainActor func `Offline error preserves loaded directions during polling and updates cadence`() async throws {
        let clock = TestClock()
        let state = TestState()
        let direction = try makeDirection()
        let policy = NearbyPollingCadencePolicy(
            activeInterval: .seconds(60),
            lowPowerInterval: .seconds(180),
            offlineInterval: .seconds(30)
        )

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
                return [direction]
            },
            cadencePolicy: policy,
            powerStateProvider: { false },
            clock: clock
        )

        model.startPolling()
        await poll(until: { state.fetchCount == 1 })
        await poll(until: { clock.sleeperCount == 1 })

        #expect(model.phase == .loaded([direction]))

        // Simulate subsequent offline failure during polling
        state.isOffline = true
        clock.advance(by: .seconds(60))
        await poll(until: { state.fetchCount == 2 })
        await poll(until: { clock.sleeperCount == 1 })

        // Loaded directions must be preserved rather than flipping to failed phase
        #expect(model.phase == .loaded([direction]))

        // Cadence should now use offlineInterval (30s) instead of activeInterval (60s)
        state.isOffline = false
        clock.advance(by: .seconds(30))
        await poll(until: { state.fetchCount == 3 })

        #expect(model.phase == .loaded([direction]))
        model.stopPolling()
    }

    @Test @MainActor func `Offline location requester error transitions to offline failure message`() async {
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            },
            hasRegion: { true },
            apiServiceProvider: { nil }
        )

        await model.performRefresh()

        #expect(model.phase == .failed(Strings.nearbyOffline))
    }

    @Test @MainActor func `Non-offline fetch failure preserves loaded directions during background poll`() async throws {
        let direction = try makeDirection()
        var shouldFail = false

        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: { self.seattleFix },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in
                if shouldFail {
                    throw NSError(domain: "test.server.error", code: 500, userInfo: [NSLocalizedDescriptionKey: "Server error"])
                }
                return [direction]
            }
        )

        await model.performRefresh()
        #expect(model.phase == .loaded([direction]))

        shouldFail = true
        await model.performRefresh()

        // Background fetch failure retains loaded directions
        #expect(model.phase == .loaded([direction]))
        #expect(model.directions.count == 1)
    }

    @Test @MainActor func `Failed refresh in loaded phase marks stale and preserves directions and origin`() async throws {
        let direction = try makeDirection()
        var shouldFail = false
        var hasRegion = true
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                if shouldFail {
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
                }
                return self.seattleFix
            },
            hasRegion: { hasRegion },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { _, _ in [direction] }
        )

        await model.performRefresh()
        #expect(model.phase == .loaded([direction]))
        #expect(model.origin == self.seattleFix)
        #expect(!model.isStale)
        #expect(model.apiService != nil)

        // Offline refresh failure in loaded phase marks stale
        shouldFail = true
        await model.performRefresh()

        #expect(model.phase == .loaded([direction]))
        #expect(model.origin == self.seattleFix)
        #expect(model.isStale)

        // Successful refresh clears stale
        shouldFail = false
        await model.performRefresh()

        #expect(model.phase == .loaded([direction]))
        #expect(!model.isStale)

        // Moving outside every region drops loaded state to .noRegion (#1777 behavior)
        hasRegion = false
        await model.performRefresh()
        #expect(model.phase == .noRegion)
    }

    @Test @MainActor func `Superseded refresh drops stale location and directions results`() async throws {
        let direction1 = try makeDirection(routeID: "1_10", headsign: "Old")
        let direction2 = try makeDirection(routeID: "1_44", headsign: "New")
        let fix1 = CLLocation(latitude: 47.60, longitude: -122.33)
        let fix2 = CLLocation(latitude: 47.65, longitude: -122.30)

        final class Gate: @unchecked Sendable {
            var canProceed1 = false
        }
        let gate = Gate()

        var callCount = 0
        let model = NearbyRoutesModel(
            authorizationProvider: { .authorizedWhenInUse },
            requestAuthorization: {},
            locationRequester: {
                callCount += 1
                if callCount == 1 {
                    while !gate.canProceed1 {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    return fix1
                } else {
                    return fix2
                }
            },
            hasRegion: { true },
            apiServiceProvider: { self.makeAPIService() },
            directionsLoader: { fix, _ in
                if fix == fix1 {
                    return [direction1]
                } else {
                    return [direction2]
                }
            }
        )

        // Start refresh 1 (will pause in locationRequester)
        let task1 = Task { await model.performRefresh() }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Start refresh 2 (supersedes refresh 1)
        let task2 = Task { await model.performRefresh() }
        _ = await task2.value

        // Allow refresh 1 to finish
        gate.canProceed1 = true
        _ = await task1.value

        // State must reflect refresh 2, not refresh 1
        #expect(model.origin == fix2)
        if case .loaded(let directions) = model.phase {
            #expect(directions.first?.headsign == "New")
        } else {
            Issue.record("Expected loaded phase from refresh 2, got \(model.phase)")
        }
    }
}
