//
//  CurrentTripViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `CurrentTripViewModel`.
@Suite(.serialized)
final class CurrentTripViewModelTests: OBATestCase {
    /// Near stop 1_10020 in the fixture (NE 55th & 37th Ave NE).
    private let userLocation = CLLocation(latitude: 47.6685, longitude: -122.2883)

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Application Builder

    /// Builds an `Application` whose REST API service routes through the supplied `MockDataLoader`.
    /// - Parameters:
    ///   - dataLoader: The mock data loader that stubs HTTP responses.
    ///   - withLocation: When `false`, the location service has no current location — useful for
    ///     driving the `.noLocation` branch.
    ///   - withRegion: When `false`, places the user at Null Island (0, 0) so `RegionsService`
    ///     cannot resolve a region and `apiService` stays `nil` — useful for driving the
    ///     `.error` / no-service branch.
    private func createApplication(dataLoader: MockDataLoader, withLocation: Bool = true, withRegion: Bool = true) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locationService: LocationService
        if withLocation {
            // When withRegion is false we use a location outside every OBA region (Null Island)
            // so that RegionsService geo-selection cannot resolve a region and apiService stays nil.
            let updateLocation = withRegion ? userLocation : CLLocation(latitude: 0, longitude: 0)
            let locManager = MockAuthorizedLocationManager(
                updateLocation: updateLocation,
                updateHeading: TestData.mockHeading
            )
            locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
            locationService.startUpdates()
        } else {
            // Plain mock — `startUpdatingLocation` flips a bool but never assigns a location,
            // so `currentLocation` stays `nil`.
            let locManager = LocationManagerMock()
            locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        }

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: withRegion ? Fixtures.pugetSoundRegion.name : nil
        )

        return Application(config: config)
    }

    // MARK: - Fixtures

    private let arrivalsFixture = "arrivals_and_departures_for_stop_1_10020.json"

    private func stopsFromArrivalsFixture() -> [Stop] {
        let response = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture)
        return [response.stop]
    }

    private func route30() -> Route {
        let stops = stopsFromArrivalsFixture()
        return stops.flatMap(\.routes).first { $0.id == "1_30" }!
    }

    private func makeMatchResult() -> NearbyTripMatcher.MatchResult {
        let arrivals = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture)
        return NearbyTripMatcher.MatchResult(
            arrivalDeparture: arrivals.arrivalsAndDepartures[0],
            distanceFromUser: 50
        )
    }

    // MARK: - Initial State

    @Test @MainActor
    func `Initial state is loading`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        guard case .loading = viewModel.state else {
            Issue.record("Expected initial state .loading, got \(viewModel.state)")
            return
        }
        #expect(viewModel.matchResults.isEmpty)
        #expect(viewModel.pendingNavigation == nil)
    }

    // MARK: - handle(results:)

    @Test @MainActor
    func `Handle results empty sets no results`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(results: [])

        guard case .noResults = viewModel.state else {
            Issue.record("Expected .noResults, got \(viewModel.state)")
            return
        }
        #expect(viewModel.matchResults.isEmpty)
        #expect(viewModel.pendingNavigation == nil)
    }

    @Test @MainActor
    func `Handle results single sets pending navigation`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])

        #expect(viewModel.pendingNavigation != nil)
        #expect(viewModel.pendingNavigation?.tripID == result.arrivalDeparture.tripID)
        #expect(viewModel.matchResults.count == 1)
        // State moves to `.multipleResults` so the underlying view shows the
        // single match as a tappable row instead of a permanent spinner. The
        // consumer navigates away via `pendingNavigation`; if they dismiss the
        // modal, the list is what greets them, not a frozen loading indicator.
        guard case .multipleResults = viewModel.state else {
            Issue.record("State should move to .multipleResults for single match, got \(viewModel.state)")
            return
        }
    }

    /// After the consumer handles the initial single match and clears
    /// `pendingNavigation`, a background refresh (or any re-entry into
    /// `handle(results:)`) that finds the SAME trip must not re-fire
    /// `pendingNavigation` — otherwise the user is snapped back to the modal
    /// they just dismissed every 20 seconds.
    @Test @MainActor
    func `Handle results repeat single match does not refire pending navigation`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])
        #expect(viewModel.pendingNavigation != nil)

        // Consumer acknowledges by clearing pendingNavigation (mirrors what the
        // SwiftUI `.onChange(of: pendingNavigation)` handler does).
        viewModel.clearPendingNavigation()

        // Same trip surfaces again on the next timer tick.
        viewModel.handle(results: [result])

        #expect(viewModel.pendingNavigation == nil)
        #expect(viewModel.matchResults.count == 1)
    }

    /// A user-initiated retry (`findVehicle()` with `resetState: true`, the
    /// default) must clear the "already presented" latch — otherwise tapping
    /// Try Again after dismissing a single-match modal would silently no-op.
    @Test @MainActor
    func `Find vehicle user initiated retry clears presented latch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])
        #expect(viewModel.pendingNavigation != nil)
        viewModel.clearPendingNavigation()

        // User taps Try Again. resetState:true (default) resets to .loading
        // and clears the latch; because there's no location, the task terminates
        // in .noLocation before ever calling handle(results:).
        viewModel.findVehicle()
        guard case .loading = viewModel.state else {
            Issue.record("findVehicle() should reset to .loading, got \(viewModel.state)")
            return
        }

        // Simulate the next find returning the same trip — pendingNavigation
        // must fire again because the latch was cleared.
        viewModel.handle(results: [result])
        #expect(viewModel.pendingNavigation != nil)
        #expect(viewModel.pendingNavigation?.tripID == result.arrivalDeparture.tripID)
    }

    /// A background refresh (`findVehicle(resetState: false)`) must NOT reset
    /// the UI to `.loading` — the whole point of splitting the two entry points
    /// is to keep the user's screen intact between the 20-second ticks.
    @Test @MainActor
    func `Find vehicle background refresh preserves state`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        // Park the VM in `.multipleResults` — a state a real user could be
        // looking at when the background refresh fires.
        let first = makeMatchResult()
        let second = makeMatchResult()
        viewModel.handle(results: [first, second])
        guard case .multipleResults = viewModel.state else {
            Issue.record("Precondition: expected .multipleResults, got \(viewModel.state)")
            return
        }

        // Simulate a timer tick. `resetState: false` skips the `.loading` reset;
        // the task will still resolve to `.noLocation` async (no location
        // configured), but the crucial assertion is *synchronous*: the state
        // must NOT have flipped to `.loading` before the task runs.
        viewModel.findVehicle(resetState: false)
        guard case .multipleResults = viewModel.state else {
            Issue.record("Background refresh must preserve .multipleResults, got \(viewModel.state)")
            return
        }

        viewModel.deactivate()
    }

    // MARK: - State.==

    /// Two `.error` cases compare equal iff their `localizedDescription`s match
    /// — SwiftUI's `.onChange(of: state)` depends on this to decide when to
    /// fire failure haptics, so a typo here would silently break the trigger.
    @Test @MainActor
    func `State equality error compares by localized description`() throws {
        let errorA1 = NSError(domain: "A", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let errorA2 = NSError(domain: "B", code: 2, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let errorB = NSError(domain: "C", code: 3, userInfo: [NSLocalizedDescriptionKey: "different"])

        #expect(CurrentTripViewModel.State.error(errorA1) == CurrentTripViewModel.State.error(errorA2))
        #expect(CurrentTripViewModel.State.error(errorA1) != CurrentTripViewModel.State.error(errorB))
        // Cross-case: `.error` never equals a non-error case.
        #expect(CurrentTripViewModel.State.error(errorA1) != CurrentTripViewModel.State.loading)
        #expect(CurrentTripViewModel.State.error(errorA1) != CurrentTripViewModel.State.multipleResults)
    }

    @Test @MainActor
    func `Handle results multiple sets multiple results`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let first = makeMatchResult()
        let second = makeMatchResult()
        viewModel.handle(results: [first, second])

        guard case .multipleResults = viewModel.state else {
            Issue.record("Expected .multipleResults, got \(viewModel.state)")
            return
        }
        #expect(viewModel.matchResults.count == 2)
        #expect(viewModel.pendingNavigation == nil)
    }

    // MARK: - handle(error:)

    @Test @MainActor
    func `Handle error no realtime data sets no realtime`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(error: NearbyTripMatcher.MatchError.noRealtimeData)

        guard case .noRealtime = viewModel.state else {
            Issue.record("Expected .noRealtime, got \(viewModel.state)")
            return
        }
    }

    @Test @MainActor
    func `Handle error generic error sets error state`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let underlying = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        viewModel.handle(error: underlying)

        guard case .error(let surfaced) = viewModel.state else {
            Issue.record("Expected .error, got \(viewModel.state)")
            return
        }
        #expect((surfaced as NSError).code == 42)
    }

    /// `noStopsNearby` is a benign geographic condition — no failure haptic, no log noise,
    /// and no retry button that can't help. It maps to `.noResults`, not `.error`.
    @Test @MainActor
    func `Handle error no stops nearby sets no results`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(error: NearbyTripMatcher.MatchError.noStopsNearby)

        guard case .noResults = viewModel.state else {
            Issue.record("Expected .noResults for .noStopsNearby, got \(viewModel.state)")
            return
        }
    }

    // MARK: - pendingNavigationUnavailable()

    /// When the UIKit consumer cannot perform single-match navigation (no embedded
    /// `UINavigationController`), the VM falls back to the disambiguation list so
    /// the user can still tap through. `matchResults` is preserved from `handle(results:)`.
    @Test @MainActor
    func `Pending navigation unavailable falls back to multiple results`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])
        #expect(viewModel.pendingNavigation != nil)
        #expect(viewModel.matchResults.count == 1)

        viewModel.pendingNavigationUnavailable()

        guard case .multipleResults = viewModel.state else {
            Issue.record("Expected .multipleResults, got \(viewModel.state)")
            return
        }
        #expect(viewModel.pendingNavigation == nil)
        // The single match must still be available so the user can tap through.
        #expect(viewModel.matchResults.count == 1)
    }

    // MARK: - Lifecycle

    /// `start()` must kick off `findVehicle()` — guards against a future refactor
    /// accidentally turning it into a no-op (e.g. only starting the timer).
    @Test @MainActor
    func `Start invokes find vehicle`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.start()
        for _ in 0..<5 { await Task.yield() }

        guard case .noLocation = viewModel.state else {
            Issue.record("Expected start() to kick findVehicle() into the no-location branch, got \(viewModel.state)")
            return
        }

        viewModel.deactivate()
    }

    // MARK: - findVehicle()

    @Test @MainActor
    func `Find vehicle no location sets no location state`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.findVehicle()
        for _ in 0..<5 { await Task.yield() }

        guard case .noLocation = viewModel.state else {
            Issue.record("Expected .noLocation, got \(viewModel.state)")
            return
        }
    }

    @Test @MainActor
    func `Find vehicle no API service sets error state`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: true, withRegion: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.findVehicle()
        await poll(until: {
            if case .error = viewModel.state { true } else { false }
        }, "Expected .error for nil apiService, got \(viewModel.state)")

        guard case .error(let error) = viewModel.state else {
            Issue.record("Expected .error for nil apiService, got \(viewModel.state)")
            return
        }
        #expect((error as NSError).domain == "CurrentTripViewModel")
    }

}
