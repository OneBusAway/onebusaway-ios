//
//  AppSheetViewFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Foundation
import Testing
import CoreLocation
import MapKit
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// Per-route factory branch coverage. Each branch that's been "wired up"
/// (i.e. removed from the shared `unimplementedView` catch-all) gets a
/// dedicated test so a future refactor that accidentally drops the branch
/// back into the catch-all fails the suite.
@Suite(.serialized)
final class AppSheetViewFactoryTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// The coordinator, display model, stops observer, and trip planner display model are required dependencies,
    /// so every test builds the factory the same way the app does.
    @MainActor
    private func makeFactory(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute> = SheetCoordinator(root: .home),
        displayModel: MapSearchDisplayModel = MapSearchDisplayModel(),
        stopsObserver: MapStopsObserver? = nil,
        tripPlannerMapDisplayModel: TripPlannerMapDisplayModel? = nil
    ) -> AppSheetViewFactory {
        AppSheetViewFactory(
            application: application,
            mapViewModel: MapViewModel(application: application),
            layersModel: MapPanelLayersModel(application: application),
            onPresentTrip: { _ in },
            onPresentVehicleTrip: { _ in },
            presentingController: { nil },
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver ?? MapStopsObserver(application: application),
            tripPlannerMapDisplayModel: tripPlannerMapDisplayModel ?? TripPlannerMapDisplayModel()
        )
    }

    @Test @MainActor
    func `More view returns more sheet host forwarding application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let host = makeFactory(application: application).moreView()

        // Reference identity: the factory must forward its own `Application`
        // into the host, not construct a new one or drop it. `MoreSheetHost`'s
        // wiring itself (produces a UINavigationController wrapping
        // MoreViewController) is covered by MoreSheetHostTests — this test
        // owns the factory-to-host handoff only.
        #expect(host.application === application)
    }

    @Test @MainActor
    func `Stop detail view returns the SwiftUI sheet forwarding the stop ID`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).stopDetailView(stopID: "1_10914")

        #expect(view.stopID == "1_10914")
    }

    /// The stop sheet takes its dependencies as factory closures rather than as
    /// built objects, because SwiftUI decides when they are instantiated. That
    /// moves the handoff `More view returns more sheet host forwarding
    /// application` checks by reference into the closures, so this asserts it
    /// there instead: both must resolve against the factory's own `Application`,
    /// not a second one.
    @Test @MainActor
    func `Stop detail view's factories resolve against the factory's application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).stopDetailView(stopID: "1_10914")

        #expect(view.makePresenter().application === application)
        #expect(view.makeViewModel().stopID == "1_10914")
        // The remaining dependencies are handed over already built, so they can
        // be compared directly.
        #expect(view.formatters === application.formatters)
        #expect(view.userDefaults === application.userDefaults)
    }

    @Test @MainActor
    func `Route stops view returns route stops sheet view forwarding the stops for route`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        let view = makeFactory(application: application).routeStopsView(stopsForRoute: stopsForRoute)

        #expect(view.stopsForRoute.route.id == stopsForRoute.route.id)
    }

    /// The route-stops sheet clears the map on dismissal, so it has to be handed the
    /// same display model the map renders — not a private one.
    @Test @MainActor
    func `Route stops view forwards the shared display model`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let displayModel = MapSearchDisplayModel()
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        let factory = makeFactory(application: application, displayModel: displayModel)
        let view = factory.routeStopsView(stopsForRoute: stopsForRoute)

        #expect(view.displayModel === displayModel)
    }

    /// Both search surfaces have to route a picked result through the *same* router,
    /// or the two screens can drift on what "opening a result" means.
    @Test @MainActor
    func `Search results view is handed the factory's shared router`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let request = SearchRequest(query: "test", type: .stopNumber)
        let response = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)

        let factory = makeFactory(application: application)
        let view = factory.searchResultsView(response: response)

        #expect(view.router === factory.searchResultRouter)
        #expect(view.application === application)
    }

    @Test @MainActor
    func `Search view returns search sheet view forwarding the placeholder`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).searchView()

        #expect(view.placeholder == SearchPlaceholder.text(for: application))
        #expect(!view.placeholder.isEmpty)
    }

    /// `.bookmarksAll` renders the native index, not the placeholder. With all
    /// three index routes wired, no route reaches `indexPlaceholderView` any
    /// more — it survives only as `unimplementedView`'s release-build fallback.
    @Test @MainActor
    func `Bookmarks all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).bookmarksAllView()

        #expect(view.application === application)
    }

    /// `.nearbyAll` carries no coordinate, so the factory resolves one from the
    /// map's settled viewport.
    ///
    /// Asserts against a *seeded* centre rather than against a second call to
    /// `NearbyCoordinateResolver` with the same inputs: recomputing the
    /// expectation the same way the factory does would pass even if the factory
    /// read the wrong sources — swapping location for region, or dropping the
    /// viewport entirely. `NearbyCoordinateResolverTests` covers the preference
    /// order; what's under test here is that the factory hands it the right
    /// three things.
    @Test @MainActor
    func `Nearby all view resolves the settled viewport center`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)

        // A deliberately implausible anchor: far from both the device location
        // and any region centre, so only the viewport could have produced it.
        let settled = CLLocationCoordinate2D(latitude: 12.345, longitude: 54.321)
        stopsObserver.updateViewport(
            MKCoordinateRegion(
                center: settled,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
        )
        try #require(stopsObserver.viewportCenter != nil)

        let view = makeFactory(application: application, stopsObserver: stopsObserver).nearbyAllView()

        #expect(view.coordinate?.latitude == settled.latitude)
        #expect(view.coordinate?.longitude == settled.longitude)
    }

    /// The second link in the chain: with no settled viewport, the anchor is the
    /// device's fix. Asserting it separately from the region centre is what shows
    /// the factory reads `locationService` at all — a factory that skipped
    /// straight to the region would still satisfy the viewport test above.
    @Test @MainActor
    func `Nearby all view falls back to the device location`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)

        // A published fix sends the app off to fetch agency alerts, and
        // `MockDataLoader` traps any request it has no stub for — which takes
        // the whole test process down, not just this test.
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        stopsObserver.reset()
        try #require(stopsObserver.viewportCenter == nil)

        // The mock manager publishes its fix only once updates start, which is
        // why `currentLocation` is nil until this call.
        application.locationService.startUpdatingLocation()
        let location = try #require(application.locationService.currentLocation)

        let view = makeFactory(application: application, stopsObserver: stopsObserver).nearbyAllView()

        #expect(view.coordinate?.latitude == location.coordinate.latitude)
        #expect(view.coordinate?.longitude == location.coordinate.longitude)
    }

    /// The last link: no viewport and no device fix leaves the current region's
    /// centre.
    ///
    /// The all-nil case — where the factory must hand the view nil rather than
    /// search around (0, 0) — is asserted in `NearbyCoordinateResolverTests`. It
    /// isn't reachable from here: a test `Application` is built with a fixed
    /// region, so `currentRegion` is never nil.
    @Test @MainActor
    func `Nearby all view falls back to the current region center`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)

        stopsObserver.reset()

        try #require(stopsObserver.viewportCenter == nil)
        try #require(application.locationService.currentLocation == nil)
        let region = try #require(application.currentRegion)

        let view = makeFactory(application: application, stopsObserver: stopsObserver).nearbyAllView()

        #expect(view.coordinate?.latitude == region.centerCoordinate.latitude)
        #expect(view.coordinate?.longitude == region.centerCoordinate.longitude)
    }

    /// `.nearbyStops` and `.nearbyAll` are the same screen; only the way the
    /// coordinate is obtained differs. This one carries its anchor in the route,
    /// so it must be passed through untouched.
    @Test @MainActor
    func `Nearby stops view forwards the route coordinate`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let view = makeFactory(application: application).nearbyStopsView(coordinate: coordinate)

        #expect(view.coordinate?.latitude == coordinate.latitude)
        #expect(view.coordinate?.longitude == coordinate.longitude)
    }

    /// `.recentStopsAll` renders the native index, not the placeholder.
    @Test @MainActor
    func `Recent stops all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).recentStopsAllView()

        #expect(view.application === application)
    }

    /// The trip planner sheet builds successfully when the region supports OTP
    /// and trip planning is enabled. The view is no longer routed to `unimplementedView`.
    @Test @MainActor
    func `Trip planner view builds with a valid request`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let request = TripPlannerRequest()

        let view = makeFactory(application: application).tripPlannerView(request: request)

        #expect(view.application === application)
        #expect(view.request == request)
    }

    /// The trip planner display model is shared with the map, so the sheet must
    /// receive the same instance the factory was constructed with — not a private copy.
    @Test @MainActor
    func `Trip planner view forwards the shared trip planner display model`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let displayModel = TripPlannerMapDisplayModel()
        let request = TripPlannerRequest()

        let factory = makeFactory(application: application, tripPlannerMapDisplayModel: displayModel)
        let view = factory.tripPlannerView(request: request)

        #expect(view.tripPlannerMapDisplayModel === displayModel)
    }

    // MARK: - Rental "plan a trip using this vehicle"

    /// The rental sheets plan a trip *through* the vehicle: it becomes a via
    /// point with the mode pinned to `.transitBikeRental`, matching
    /// `MapViewController.rentalLayer(planTripUsing:)` on the UIKit surface.
    /// Routing *to* the vehicle would be the wrong trip — a rider wants to ride
    /// it onward, not arrive at it.
    @Test @MainActor
    func `Rental plan trip handler pushes the vehicle as a via point in bike rental mode`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        #expect(application.regionsService.currentRegion?.supportsOTP == true)

        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let factory = makeFactory(application: application, coordinator: coordinator)
        let rental = try RentalFixtures.pedalBike(id: "b7")

        let handler = try #require(factory.planTripUsingRental)
        handler(rental)

        // `.tripPlanner` prefers stacking, so it lands on the stacked layer.
        guard case .tripPlanner(let request) = coordinator.stackedRoutes.last else {
            Issue.record("Expected .tripPlanner stacked, got \(String(describing: coordinator.stackedRoutes.last))")
            return
        }
        #expect(request.transportMode == .transitBikeRental)
        #expect(request.viaPoint?.latitude == rental.coordinate.latitude)
        #expect(request.viaPoint?.longitude == rental.coordinate.longitude)
        // The vehicle is not the destination — that field stays open for the rider.
        #expect(request.destination == nil)
    }

    /// No OTP server means no trip planner to route into, so the handler is nil
    /// and the sheets hide the button rather than showing a dead primary action.
    ///
    /// Exercises the gate directly rather than swapping the app's current region:
    /// `RegionsService.add(customRegion:)` writes to the shared on-disk regions
    /// store, and doing that mid-suite takes 17 unrelated suites down with it.
    @Test @MainActor
    func `Rental trip planning is offered only when the region has an OTP server`() {
        let noOTPRegion = Region(
            name: "No OTP Region",
            OBABaseURL: URL(string: "http://example.com")!,
            coordinateRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                latitudinalMeters: 1000.0,
                longitudinalMeters: 1000.0
            ),
            contactEmail: "test@example.com"
        )

        #expect(AppSheetViewFactory.offersTripPlanning(in: noOTPRegion) == false)
        #expect(AppSheetViewFactory.offersTripPlanning(in: nil) == false)
        #expect(AppSheetViewFactory.offersTripPlanning(in: Fixtures.pugetSoundRegion))
    }

    // MARK: - Rental cluster drill-in

    /// Tapping a row in the cluster list pushes the same `.rentalDetail` route a tap on a
    /// lone map pin opens, rather than letting the list present its own sheet.
    ///
    /// The list *can* present one — it does on the UIKit surface — but on the panel that
    /// sheet and `StackedSheetLayer`'s next route would be two presentations from one view.
    /// SwiftUI permits one ("Currently, only presenting a single sheet is supported"), so
    /// the trip planner pushed from inside the rental sheet stayed queued until the rider
    /// dismissed the rental by hand.
    @Test @MainActor
    func `Selecting a rental from the cluster list pushes the rental detail route`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let factory = makeFactory(application: application, coordinator: coordinator)
        let rental = try RentalFixtures.pedalBike(id: "b7")

        coordinator.push(.rentalCluster(memberIDs: [rental.id, "b8"]))
        factory.selectRentalFromCluster(rental)

        #expect(coordinator.stackedRoutes == [
            .rentalCluster(memberIDs: [rental.id, "b8"]),
            .rentalDetail(rentalID: rental.id)
        ])
    }

    /// The whole reported flow, as routes: cluster, then vehicle, then planner. Each is its
    /// own stacked entry, which is what gives each one its own presenting host — the
    /// property that was violated when the list presented the vehicle sheet itself.
    @Test @MainActor
    func `Cluster to vehicle to trip planner produces three distinct stacked sheets`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let factory = makeFactory(application: application, coordinator: coordinator)
        let rental = try RentalFixtures.pedalBike(id: "b7")

        coordinator.push(.rentalCluster(memberIDs: [rental.id]))
        factory.selectRentalFromCluster(rental)
        let planTrip = try #require(factory.planTripUsingRental)
        planTrip(rental)

        #expect(coordinator.stackedRoutes.count == 3)
        guard case .tripPlanner(let request) = coordinator.stackedRoutes.last else {
            Issue.record("Expected .tripPlanner on top, got \(String(describing: coordinator.stackedRoutes.last))")
            return
        }
        #expect(request.transportMode == .transitBikeRental)
        #expect(request.viaPoint?.latitude == rental.coordinate.latitude)
    }
}
