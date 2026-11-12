//
//  ViewRouterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
@MainActor
final class ViewRouterTests: OBATestCase {

    @Test func `Navigate to StopID pushes a stop controller`() throws {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        application.viewRouter.navigateTo(stopID: "1_123", from: root)

        let pushed = try #require(navigation.viewControllers.last)
        #expect(pushed !== root, "Expected a new view controller to be pushed")

        let isStopController = pushed is StopViewController || pushed is StopPageViewController
        #expect(isStopController, "Expected pushed controller to be a stop controller")
    }

    /// Both stop screens, because each draws the context its own way: the new
    /// page highlights the trip, the legacy one shows the arrival banner.
    @Test(arguments: [true, false])
    func `Navigate to StopID hands the transfer context to the stop screen`(newStopPage: Bool) throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        application.userDefaults.set(newStopPage, forKey: FeatureFlags.useNewStopPageKey)
        #expect(application.userDataStore.showTransferArrivalBanner)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_700_000_000),
            fromRouteShortName: "49",
            fromTripHeadsign: "Downtown Seattle Broadway",
            fromTripID: "1_40984902"
        )

        application.viewRouter.navigateTo(stopID: "1_123", from: root, transferContext: context)

        let pushed = try #require(navigation.viewControllers.last as? StopContextConfigurable)
        #expect((pushed is StopPageViewController) == newStopPage)
        #expect(pushed.transferContext == context)
    }

    @Test func `Navigate to StopID drops the transfer context when the transfer banner is off`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        application.userDataStore.showTransferArrivalBanner = false

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_700_000_000),
            fromRouteShortName: "49",
            fromTripHeadsign: "Downtown Seattle Broadway"
        )

        application.viewRouter.navigateTo(stopID: "1_123", from: root, transferContext: context)

        let pushed = try #require(navigation.viewControllers.last as? StopContextConfigurable)
        #expect(pushed.transferContext == nil)
    }

    /// A shared trip link: boarding at 1_75414 (row 5 of trip 1_18196913), the
    /// sharer stepping off at 1_25900 (row 20). The destination has to reach the
    /// stops the rider sees, in the list and on the map, not just be stored.
    @Test func `Navigate to arrivalDeparture pushes the trip map host, and a shared destination reaches its stop list and map`() async throws {
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        let trip = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/trip-details") ?? false }
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/arrival-and-departure-for-stop") ?? false }
        let emptyShape = Data(#"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.utf8)
        dataLoader.mock(data: emptyShape) { $0.url?.path.contains("/api/where/shape") ?? false }
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)

        // Loaded with its references, which the page reads as soon as its view
        // loads. Its own trip differs, but the stop list is built from the trip
        // details the stub answers with, where 1_75414 is row 5.
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_75414.json"
        )
        let boarding = try #require(stopArrivals.arrivalsAndDepartures.first)
        #expect(boarding.stopID == "1_75414")
        application.viewRouter.navigateTo(arrivalDeparture: boarding, from: root, destinationStopID: "1_25900")

        let host = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        host.loadViewIfNeeded()
        host.tripPage.viewModel.loadData()
        await host.tripPage.viewModel.loadDataTask?.value

        let list = host.tripPage.viewModel.stopList
        #expect(list.rows.count == 53)
        #expect(list.rows.firstIndex { $0.isUserStop } == 20)
        #expect(list.rows[20].stopID == "1_25900")
        #expect(list.rows.firstIndex { $0.isBoardingStop } == 5)

        let mapStops = try #require(host.tripPage.mapFocus.content?.stops)
        #expect(mapStops.firstIndex { $0.isUserStop } == 20)
        #expect(mapStops.firstIndex { $0.isBoardingStop } == 5)
    }

    // MARK: - Trip entry points

    /// Two arrivals at stop 1_1121 on different trips, with their references loaded.
    private func makeArrivals() throws -> [ArrivalDeparture] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures_1_1121.json"
        )
        let arrivals = Array(stopArrivals.arrivalsAndDepartures.prefix(2))
        #expect(arrivals.count == 2)
        #expect(arrivals.first?.tripID != arrivals.last?.tripID)
        return arrivals
    }

    /// My Trip found the rider's vehicle: the trip replaces My Trip on the stack,
    /// so Back returns to the route picker.
    @Test func `My Trip's single match opens the trip map host in its place`() async throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let arrival = try #require(try makeArrivals().first)
        let picker = UIViewController()
        let currentTrip = CurrentTripViewController(application: application, route: arrival.route)
        let navigation = UINavigationController(rootViewController: picker)
        navigation.pushViewController(currentTrip, animated: false)
        currentTrip.loadViewIfNeeded()

        currentTrip.viewModel.handle(results: [NearbyTripMatcher.MatchResult(arrivalDeparture: arrival, distanceFromUser: 40)])
        await poll(until: { navigation.viewControllers.last is TripMapHostViewController }, "My Trip never opened the trip")

        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.viewControllers.first === picker)
        let host = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        #expect(host.tripPage.viewModel.tripConvertible.tripID == arrival.tripID)
    }

    /// Several vehicles on the route: the rider picks one from the list.
    @Test func `My Trip's chosen match pushes the trip map host`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let arrivals = try makeArrivals()
        let currentTrip = CurrentTripViewController(application: application, route: arrivals[0].route)
        let navigation = UINavigationController(rootViewController: currentTrip)
        currentTrip.loadViewIfNeeded()

        currentTrip.viewModel.handle(results: arrivals.map { NearbyTripMatcher.MatchResult(arrivalDeparture: $0, distanceFromUser: 40) })
        let rows = try #require(currentTrip.items(for: OBAListView()).first?.contents)
        let second = try #require(rows.last)
        let select = try #require(second.onSelectAction)
        select(second)

        let host = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        #expect(host.tripPage.viewModel.tripConvertible.tripID == arrivals[1].tripID)
    }

    /// Searching the map for a vehicle number opens that vehicle's trip.
    @Test func `A vehicle search result pushes the trip map host`() async throws {
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let data = Fixtures.loadData(file: "api_where_vehicle_1_4351.json")
        let vehicle = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<VehicleStatus>.self, from: data).entry
        let map = MapViewController(application: application)
        let navigation = UINavigationController(rootViewController: map)

        let response = SearchResponse(
            request: SearchRequest(query: "4351", type: .vehicleID),
            results: [vehicle],
            boundingRegion: nil,
            error: nil
        )
        map.mapRegionManager(application.mapRegionManager, showSearchResult: response)
        await poll(until: { navigation.viewControllers.count == 2 }, "the search result never opened")

        let host = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        #expect(host.tripPage.viewModel.tripConvertible.tripID == "1_47649081")
        #expect(host.tripPage.viewModel.tripConvertible.vehicleStatus === vehicle)
    }

    // MARK: - MapPanel Deep-Link & Sheet Routing

    /// Verifies that constructing a `MapPanelRootController` registers it with
    /// `ViewRouter` and resolves dynamically from context or as fallback.
    @Test func `MapPanelRootController registers and resolves in ViewRouter`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let panel = MapPanelRootController(application: application)

        #expect(application.viewRouter.mapPanelRootController === panel)
        #expect(application.viewRouter.mapPanelRootController(from: panel) === panel)
    }

    /// Verifies `rootNavigateTo(page:)` maps tab destinations to their
    /// corresponding sheet routes in map-panel mode.
    @Test func `rootNavigateTo maps pages correctly in map panel mode`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let panel = MapPanelRootController(application: application)

        application.viewRouter.rootNavigateTo(page: .recentStops, from: panel)
        #expect(panel.coordinator.stackedRoutes.last == .recentStopsAll)

        application.viewRouter.rootNavigateTo(page: .bookmarks, from: panel)
        #expect(panel.coordinator.stackedRoutes.last == .bookmarksAll)

        application.viewRouter.rootNavigateTo(page: .more, from: panel)
        #expect(panel.coordinator.stackedRoutes.last == .more)

        application.viewRouter.rootNavigateTo(page: .map, from: panel)
        #expect(panel.coordinator.currentRoute == .home)
        #expect(panel.coordinator.stackedRoutes.isEmpty)
    }

    /// Verifies `navigate(to:)` routes directly to the floating sheet coordinator
    /// when the modern map panel is the active root controller.
    @Test func `navigate to AppSheetRoute navigates sheet coordinator in map panel mode`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let panel = MapPanelRootController(application: application)

        let handled = application.viewRouter.navigate(to: .stopDetails(stopID: "1_75403"), from: panel)
        #expect(handled)
        #expect(panel.coordinator.stackedRoutes.last == .stopDetails(stopID: "1_75403"))

        application.viewRouter.navigate(to: .home, from: panel, popToRootFirst: true)
        #expect(panel.coordinator.currentRoute == .home)
        #expect(panel.coordinator.stackedRoutes.isEmpty)
    }

    /// Verifies external navigation (`pushStopFromOutside`) pushes a stop sheet
    /// into the map panel without dropping when map-panel mode is active.
    @Test func `pushStopFromOutside routes into map panel coordinator when map panel is active`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let panel = MapPanelRootController(application: application)

        application.pushStopFromOutside("1_9999")
        #expect(panel.coordinator.stackedRoutes.last == .stopDetails(stopID: "1_9999"))
    }

    /// Verifies `navigateTo(stopID:from:)` with a controller lacking a navigation controller
    /// routes into the map panel sheet coordinator without tripping assertions.
    @Test func `navigateTo stopID from bare controller in map panel mode routes into sheet coordinator`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let panel = MapPanelRootController(application: application)

        let child = UIViewController()
        panel.addChild(child)
        panel.view.addSubview(child.view)
        child.didMove(toParent: panel)

        application.viewRouter.navigateTo(stopID: "1_4321", from: child)
        #expect(panel.coordinator.stackedRoutes.last == .stopDetails(stopID: "1_4321"))
    }

    /// Verifies opening a custom scheme URL (`onebusaway://stop?id=...`)
    /// through `Application.application(_:open:options:)` routes into the sheet coordinator.
    @Test func `opening custom scheme stop URL routes to stop sheet in map panel mode`() throws {
        let dataLoader = MockDataLoader(testName: "ViewRouterTests")
        dataLoader.mock(data: Fixtures.loadData(file: "pugetsound-weather.json")) {
            $0.url?.path.contains("/weather.json") ?? false
        }

        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let panel = MapPanelRootController(application: application)

        let window = UIWindow(windowScene: try testWindowScene())
        window.rootViewController = panel
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let delegate = TestAppDelegate()
        delegate.uiApplication = .shared
        application.delegate = delegate

        let customURL = try #require(URL(string: "onebusaway://stop?id=1_75403"))
        let handled = application.application(UIApplication.shared, open: customURL, options: [:])
        #expect(handled)
        #expect(panel.coordinator.stackedRoutes.last == .stopDetails(stopID: "1_75403"))
    }

    /// Verifies `navigate(to: AppSheetRoute)` translates sheet routes into tab switches
    /// when classic mode (`ClassicApplicationRootController`) is active.
    @Test func `navigate to AppSheetRoute translates to classic tabs when classic mode is active`() throws {
        let application = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: "ViewRouterTests"))
        let classicRoot = ClassicApplicationRootController(application: application)

        #expect(application.viewRouter.rootController === classicRoot)

        let handledRecent = application.viewRouter.navigate(to: .recentStopsAll)
        #expect(handledRecent)
        #expect(classicRoot.selectedIndex == ClassicApplicationRootController.Page.recentStops.rawValue)

        let handledBookmarks = application.viewRouter.navigate(to: .bookmarksAll)
        #expect(handledBookmarks)
        #expect(classicRoot.selectedIndex == ClassicApplicationRootController.Page.bookmarks.rawValue)

        let handledMore = application.viewRouter.navigate(to: .more)
        #expect(handledMore)
        #expect(classicRoot.selectedIndex == ClassicApplicationRootController.Page.more.rawValue)

        let handledHome = application.viewRouter.navigate(to: .home)
        #expect(handledHome)
        #expect(classicRoot.selectedIndex == ClassicApplicationRootController.Page.map.rawValue)
    }
}
