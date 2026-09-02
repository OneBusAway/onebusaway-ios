//
//  TripSharingCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Records what the coordinator presented, and when.
///
/// Extends `MockPresentingViewController` rather than replacing it: that helper
/// tracks `present` but not `dismiss`, and `TripSharingCoordinator` does all of
/// its work inside `dismiss`'s completion block — the ordering these tests exist
/// to pin.
///
/// With `autoRunsDismissCompletion` false, `dismiss(animated:completion:)` parks
/// the completion instead of running it, so a test can observe the window
/// between "picker dismissed" and "share sheet presented".
private final class RecordingPresenter: MockPresentingViewController {
    enum Call: Equatable {
        case dismiss
        case present
    }

    private(set) var calls: [Call] = []
    private(set) var presentedControllers: [UIViewController] = []
    private var parkedDismissCompletion: (() -> Void)?

    var autoRunsDismissCompletion = true

    /// The share sheet the coordinator presented, if it got that far.
    var sharedActivityController: UIActivityViewController? {
        presentedControllers.compactMap { $0 as? UIActivityViewController }.last
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        calls.append(.present)
        presentedControllers.append(viewControllerToPresent)
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        calls.append(.dismiss)

        guard autoRunsDismissCompletion else {
            parkedDismissCompletion = completion
            return
        }
        completion?()
    }

    /// Runs the completion block parked by the most recent `dismiss`.
    func finishDismissal() {
        let completion = parkedDismissCompletion
        parkedDismissCompletion = nil
        completion?()
    }
}

/// Covers `TripSharingCoordinator` — the piece both the legacy
/// `StopViewController` and the redesigned stop page depend on for trip sharing.
///
/// `AppLinksRouterDeepLinkFormatTests` builds its `URLComponents` by hand and
/// never calls `AppLinksRouter.encode`, so the `destination_stop_id` encoding is
/// exercised here through the production API instead.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/449
@Suite(.serialized)
final class TripSharingCoordinatorTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// The fixture's first arrival: tripID `1_40984902`, stopID `1_10914`,
    /// stopSequence `3`, serviceDate `1541055600000`ms. Every expected URL below
    /// is spelled out from those values rather than recomputed from the model,
    /// so an encoding change has to be acknowledged rather than tracked.
    private func makeArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    /// A `TripStopTime` carrying just the one field the coordinator reads.
    private func makeStopTime(stopID: StopID) throws -> TripStopTime {
        try Fixtures.dictionaryToModel(
            type: TripStopTime.self,
            dictionary: ["stopId": stopID, "arrivalTime": 0, "departureTime": 0]
        )
    }

    private func registerBaseStubs(on dataLoader: MockDataLoader) {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let emptySurveys = Data(#"{"surveys":[]}"#.utf8)
        dataLoader.mock(data: emptySurveys) { $0.url?.path.contains("/surveys.json") ?? false }
    }

    /// Builds an `Application` pinned to Puget Sound, whose `sidecarBaseURL`
    /// (`https://onebusaway.co`) is what `AppLinksRouter` builds share URLs from.
    ///
    /// - Parameters:
    ///   - bundledRegionsFixture: pass `regions-puget-sound-no-sidecar.json` for a
    ///     region that exists but has no sidecar URL — the only input that makes
    ///     `AppLinksRouter.encode` return nil.
    ///   - location: pass Null Island with `pinsRegion: false` to leave
    ///     `currentRegion` nil.
    private func createApplication(
        dataLoader: MockDataLoader,
        bundledRegionsFixture: String? = nil,
        location: CLLocation = TestData.mockSeattleLocation,
        pinsRegion: Bool = true
    ) -> Application {
        registerBaseStubs(on: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: location,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsFixture.map { Fixtures.path(to: $0) } ?? bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: pinsRegion ? Fixtures.pugetSoundRegion.name : nil
        )

        return Application(config: config)
    }

    /// `RegionsService` prefers the on-disk regions file over the bundled one, and
    /// a prior run in the same simulator can leave a copy that *does* have a
    /// sidecar URL. Wipe it so a no-sidecar bundled fixture actually reaches
    /// `currentRegion`.
    private func removeStoredRegionsFile() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        try? FileManager.default.removeItem(
            at: appSupport.appendingPathComponent("Regions/default-regions.json")
        )
    }

    // MARK: - destination_stop_id encoding

    /// The gap the hand-built deep-link tests leave open: this goes through
    /// `AppLinksRouter.encode`, the call the coordinator actually makes.
    @Test @MainActor
    func `Encoded share URL carries the destination stop alongside the trip identifiers`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let region = try #require(app.currentRegion)
        let router = try #require(app.appLinksRouter)

        let url = try #require(router.encode(
            arrivalDeparture: arrivalDeparture,
            region: region,
            destinationStopID: "1_431"
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "onebusaway.co")
        #expect(components.path == "/regions/1/stops/1_10914/trips")
        #expect(components.queryItem(named: "destination_stop_id")?.value == "1_431")
        #expect(components.queryItem(named: "trip_id")?.value == "1_40984902")
        #expect(components.queryItem(named: "service_date")?.value == "1541055600.0")
        #expect(components.queryItem(named: "stop_sequence")?.value == "3")
    }

    /// A nil destination must omit the query item outright. An empty
    /// `destination_stop_id=` would reach the sidecar as a stop ID matching
    /// nothing, which is worse than saying nothing at all.
    @Test @MainActor
    func `Encoded share URL omits the destination query item when there is no destination`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let region = try #require(app.currentRegion)
        let router = try #require(app.appLinksRouter)

        let url = try #require(router.encode(
            arrivalDeparture: arrivalDeparture,
            region: region,
            destinationStopID: nil
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItem(named: "destination_stop_id") == nil)
        #expect(components.queryItems?.count == 3)
        #expect(components.path == "/regions/1/stops/1_10914/trips")
        #expect(components.queryItem(named: "trip_id")?.value == "1_40984902")
    }

    // MARK: - Delegate paths
    //
    // `UIActivityViewController` does not expose its `activityItems`, so the URL
    // a presented share sheet carries cannot be read back here. Which destination
    // each delegate method forwards to `encode` is pinned by the encoding tests
    // above; these pin that each method reaches the share sheet at all — and that
    // cancel does not.

    @Test @MainActor
    func `Selecting a destination stop dismisses the picker and shares`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let presenter = RecordingPresenter()
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPicker(picker, didSelectStop: try makeStopTime(stopID: "1_431"))

        #expect(presenter.calls == [.dismiss, .present])
        #expect(presenter.sharedActivityController != nil, "Selecting a stop must reach the share sheet")
        #expect(presenter.presentedAlert == nil, "The happy path must not surface the failure alert")
    }

    @Test @MainActor
    func `Skipping the destination dismisses the picker and shares`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let presenter = RecordingPresenter()
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPickerDidSkipDestination(picker)

        #expect(presenter.calls == [.dismiss, .present])
        #expect(
            presenter.sharedActivityController != nil,
            "The destination is optional — skipping it must still reach the share sheet"
        )
        #expect(presenter.presentedAlert == nil)
    }

    @Test @MainActor
    func `Cancelling dismisses the picker without sharing`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let presenter = RecordingPresenter()
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPickerDidCancel(picker)

        #expect(presenter.calls == [.dismiss], "Cancel dismisses and stops there")
        #expect(presenter.sharedActivityController == nil)
        #expect(presenter.presentedAlert == nil)
    }

    // MARK: - Dismiss-then-present ordering

    /// The share sheet must be presented from `dismiss`'s completion block, once
    /// the picker is actually gone — presenting on top of a still-dismissing
    /// controller is the bug this ordering avoids.
    ///
    /// Parking the completion instead of running it inline is what makes this
    /// discriminating: a coordinator that presented alongside `dismiss` rather
    /// than inside its completion would present here, with the completion never
    /// run at all.
    @Test @MainActor
    func `Share sheet is presented from the dismiss completion, not alongside it`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let arrivalDeparture = try makeArrivalDeparture()

        let presenter = RecordingPresenter()
        presenter.autoRunsDismissCompletion = false
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPicker(picker, didSelectStop: try makeStopTime(stopID: "1_431"))

        #expect(presenter.calls == [.dismiss], "Nothing may be presented while the picker is still dismissing")
        #expect(presenter.sharedActivityController == nil)

        presenter.finishDismissal()

        #expect(presenter.calls == [.dismiss, .present])
        #expect(presenter.sharedActivityController != nil, "The share sheet belongs in the dismiss completion")
    }

    // MARK: - Unable to Share

    /// First `presentShareError()` guard: no current region.
    @Test @MainActor
    func `Sharing without a current region surfaces the failure alert`() throws {
        let dataLoader = MockDataLoader(testName: name)
        // Null Island (0, 0), in the Gulf of Guinea, is covered by no transit
        // region — and with no `fixedRegionName` pinning one, `currentRegion`
        // stays nil.
        let app = createApplication(
            dataLoader: dataLoader,
            location: CLLocation(latitude: 0, longitude: 0),
            pinsRegion: false
        )
        #expect(app.currentRegion == nil, "Precondition: the guard under test needs a nil region")

        let arrivalDeparture = try makeArrivalDeparture()
        let presenter = RecordingPresenter()
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPickerDidSkipDestination(picker)

        let alert = try #require(presenter.presentedAlert, "A missing region must not fail silently")
        #expect(alert.title == "Unable to Share")
        #expect(alert.actions.first?.title == "Dismiss", "The alert needs a way out")
        #expect(presenter.sharedActivityController == nil, "No share sheet when the link cannot be built")
    }

    /// Second `presentShareError()` guard: `encode` returns nil. The region is
    /// present, so the first guard passes, but it carries no `sidecarBaseURL` —
    /// the only input that makes `AppLinksRouter.encode` fail.
    @Test @MainActor
    func `Sharing from a region with no sidecar URL surfaces the failure alert`() throws {
        removeStoredRegionsFile()

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(
            dataLoader: dataLoader,
            bundledRegionsFixture: "regions-puget-sound-no-sidecar.json"
        )
        let arrivalDeparture = try makeArrivalDeparture()

        let region = try #require(app.currentRegion, "Precondition: this guard needs a region that does exist")
        #expect(region.sidecarBaseURL == nil)

        let router = try #require(app.appLinksRouter)
        #expect(
            router.encode(arrivalDeparture: arrivalDeparture, region: region, destinationStopID: "1_431") == nil,
            "Precondition: encode must fail here, or the coordinator never reaches the guard under test"
        )

        let presenter = RecordingPresenter()
        let coordinator = TripSharingCoordinator(application: app, presenter: presenter)
        let picker = DestinationStopPickerController(application: app, arrivalDeparture: arrivalDeparture)

        coordinator.destinationStopPicker(picker, didSelectStop: try makeStopTime(stopID: "1_431"))

        let alert = try #require(presenter.presentedAlert, "A failed encode must not fail silently")
        #expect(alert.title == "Unable to Share")
        #expect(presenter.sharedActivityController == nil)
    }
}
