//
//  TripMapHostViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKitCore
@testable import OBAKit

/// The trip page hosted over a map of its own: what the host draws, how the
/// embedded page finds its way back, and what a tap on the map opens.
@Suite(.serialized)
@MainActor
final class TripMapHostViewControllerTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow?

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
        window?.rootViewController = nil
        window?.isHidden = true
    }

    // MARK: - Helpers

    /// An application whose trip loads are answered, so a host can go on screen.
    private func makeApplication(dataLoader: MockDataLoader) -> Application {
        let trip = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/trip-details") ?? false }
        dataLoader.mock(data: trip) { $0.url?.path.contains("/api/where/arrival-and-departure-for-stop") ?? false }
        let emptyShape = Data(#"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.utf8)
        dataLoader.mock(data: emptyShape) { $0.url?.path.contains("/api/where/shape") ?? false }
        dataLoader.mock(data: Data(#"{"surveys":[]}"#.utf8)) { $0.url?.path.contains("/surveys.json") ?? false }
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        return buildApplication(queue: queue, dataLoader: dataLoader)
    }

    /// Route 49 to Downtown Seattle Broadway, boarding at stop 1_10914.
    private func makeDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try #require(stopArrivals.arrivalsAndDepartures.first)
    }

    private func row(index: Int, stopID: StopID, arrival: TimeInterval, coordinate: CLLocationCoordinate2D? = nil) -> TripStopListModel.Row {
        TripStopListModel.Row(
            id: "\(index)-\(stopID)",
            stopID: stopID,
            name: "Stop \(index)",
            coordinate: coordinate,
            date: Date(timeIntervalSince1970: arrival),
            isPassed: false,
            isVehicleHere: false,
            isUserStop: false,
            isTerminal: false
        )
    }

    /// A stack on screen, so pushes and pops run the appearance callbacks.
    private func show(_ navigation: UINavigationController) throws -> UIWindow {
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = navigation
        window.isHidden = false
        window.layoutIfNeeded()
        self.window = window
        return window
    }

    private func push(_ viewController: UIViewController, onto navigation: UINavigationController, in window: UIWindow) {
        navigation.pushViewController(viewController, animated: false)
        window.layoutIfNeeded()
    }

    private func pop(_ navigation: UINavigationController, in window: UIWindow) {
        navigation.popViewController(animated: false)
        window.layoutIfNeeded()
    }

    // MARK: - Map

    @Test func `The page's map focus draws the trip on the host's map, and nil clears it`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let host = TripMapHostViewController(application: application, arrivalDeparture: try makeDeparture())
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        host.tripPage.mapFocus.apply(TripMapFocus.Content(
            tripID: "1_40984902",
            routeColor: .systemRed,
            routeType: .bus,
            shape: [],
            progress: nil,
            stops: [
                row(index: 0, stopID: "1_10914", arrival: 1_541_142_000, coordinate: CLLocationCoordinate2D(latitude: 47.61, longitude: -122.33)),
                row(index: 1, stopID: "1_10920", arrival: 1_541_142_600, coordinate: CLLocationCoordinate2D(latitude: 47.62, longitude: -122.32))
            ],
            vehicle: nil
        ))
        let stopDots = { host.mapView.annotations.compactMap { $0 as? TripStopAnnotation }.map(\.row.stopID).sorted() }
        #expect(stopDots().isEmpty)

        host.tripPage.onMapFocusChanged?(host.tripPage.mapFocus)
        #expect(stopDots() == ["1_10914", "1_10920"])

        host.tripPage.onMapFocusChanged?(nil)
        #expect(stopDots().isEmpty)
    }

    /// The stop opens with the trip's arrival time there, as tapping its row does.
    @Test func `Tapping a stop's dot opens the stop with the transfer context`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let host = TripMapHostViewController(application: application, arrivalDeparture: try makeDeparture())
        let navigation = UINavigationController(rootViewController: host)
        host.loadViewIfNeeded()

        let dot = TripStopAnnotation(
            row: row(index: 6, stopID: "1_10920", arrival: 1_541_142_600),
            coordinate: CLLocationCoordinate2D(latitude: 47.62, longitude: -122.32),
            routeColor: .systemRed
        )
        host.mapView(host.mapView, didSelect: MKAnnotationView(annotation: dot, reuseIdentifier: nil))

        #expect(navigation.viewControllers.count == 2)
        let stop = try #require(navigation.viewControllers.last as? StopContextConfigurable)
        let context = try #require(stop.transferContext)
        #expect(context.arrivalTime == Date(timeIntervalSince1970: 1_541_142_600))
        #expect(context.fromTripID == "1_40984902")

        let analytics = try #require(application.analytics as? AnalyticsMock)
        #expect(analytics.reportedEvents.filter { $0.label == AnalyticsLabels.mapStopAnnotationTapped }.count == 1)
    }

    @Test func `Camera insets keep the trip clear of the panel`() {
        let phone = TripMapHostViewController.cameraInsets(
            mapSize: CGSize(width: 390, height: 844),
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            safeAreaHeight: 763,
            panelCoverage: .bottomHalf
        )
        // 34 pt home indicator + half of the 763 pt safe area, + 8 pt margin.
        #expect(phone.bottom == 423.5)
        #expect(phone.top == 55)

        let iPad = TripMapHostViewController.cameraInsets(
            mapSize: CGSize(width: 1024, height: 768),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            safeAreaHeight: 724,
            panelCoverage: .leading
        )
        // 8 pt inset + the 291 pt column, + 8 pt margin.
        #expect(iPad.left == 307)
        #expect(iPad.bottom == 28)

        let preview = TripMapHostViewController.cameraInsets(
            mapSize: CGSize(width: 390, height: 844),
            safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
            safeAreaHeight: 763,
            panelCoverage: .none
        )
        #expect(preview.bottom == 42)
    }

    /// The map's legal label, scale and compass stay in the strip of map the
    /// panel leaves uncovered.
    @Test func `Map margins keep the map's own labels clear of the panel`() {
        let half = TripMapHostViewController.mapLayoutMargins(panelState: .half, panelCoverage: .bottomHalf, safeAreaHeight: 763)
        #expect(half == UIEdgeInsets(top: 0, left: 0, bottom: 381.5, right: 0))

        let tip = TripMapHostViewController.mapLayoutMargins(panelState: .tip, panelCoverage: .bottomHalf, safeAreaHeight: 763)
        #expect(tip == UIEdgeInsets(top: 0, left: 0, bottom: 72, right: 0))

        // 291 pt column + 8 pt padding, on the physical left.
        let iPad = TripMapHostViewController.mapLayoutMargins(panelState: .half, panelCoverage: .leading, safeAreaHeight: 724)
        #expect(iPad == UIEdgeInsets(top: 0, left: 299, bottom: 0, right: 0))

        let preview = TripMapHostViewController.mapLayoutMargins(panelState: .half, panelCoverage: .none, safeAreaHeight: 763)
        #expect(preview == .zero)
    }

    /// Read back, a view's margins include its safe area, which is subtracted
    /// here to leave the margin the host set.
    @Test func `On screen, the map's margins follow the panel`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)
        push(host, onto: navigation, in: window)
        let setBottom = { host.mapView.layoutMargins.bottom - host.mapView.safeAreaInsets.bottom }
        #expect(host.floatingPanel.state == .half)
        #expect(setBottom() == host.view.safeAreaLayoutGuide.layoutFrame.height / 2)

        host.floatingPanel.move(to: .tip, animated: false)
        #expect(setBottom() == 72)
    }

    // MARK: - Panel

    @Test func `The panel at its tip collapses the page, and leaving the tip expands it`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)
        push(host, onto: navigation, in: window)
        #expect(!host.tripPage.rootView.isCollapsed)

        host.floatingPanel.move(to: .tip, animated: false)
        #expect(host.tripPage.rootView.isCollapsed)

        host.floatingPanel.move(to: .half, animated: false)
        #expect(!host.tripPage.rootView.isCollapsed)
    }

    @Test func `A preview shows the map alone, and committing it brings up the panel`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let host = TripMapHostViewController(application: application, arrivalDeparture: try makeDeparture())

        host.enterPreviewMode()
        host.loadViewIfNeeded()
        #expect(host.floatingPanel.view.isHidden)
        // Still embedded, so the page can load the trip the map draws.
        #expect(host.tripPage.parent === host.floatingPanel)

        host.exitPreviewMode()
        #expect(!host.floatingPanel.view.isHidden)
    }

    // MARK: - Embedding

    /// The page's appearance work (the idle timer, Handoff, the trip's loads and
    /// the map focus) runs once for the host appearing: the panel forwards
    /// appearance to the page, and nothing else may. Counted through the map
    /// focus, the one step of that work a test can see.
    @Test func `Showing the host runs the page's appearance work once`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        var appearances = 0
        host.tripPage.onMapFocusChanged = { focus in
            if focus != nil { appearances += 1 }
        }
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(host, onto: navigation, in: window)

        #expect(appearances == 1)
    }

    @Test func `The page's Back pops the host`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let window = try show(navigation)
        push(host, onto: navigation, in: window)
        #expect(host.tripPage.backBehavior == .pop)

        host.tripPage.rootView.actions.onBack()
        window.layoutIfNeeded()

        #expect(navigation.viewControllers == [root])
    }

    /// What the trip starts as or continues as opens full screen too, over a map
    /// of its own, and Back returns to this trip.
    @Test func `A trip the page opens is pushed in a host of its own`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let host = TripMapHostViewController(application: application, arrivalDeparture: try makeDeparture())
        let navigation = UINavigationController(rootViewController: host)
        host.tripPage.openTrip(try Fixtures.tripConvertible(tripID: "trip_43"))

        #expect(navigation.viewControllers.count == 2)
        let pushed = try #require(navigation.viewControllers.last as? TripMapHostViewController)
        // By ID: a failing expectation describes its operands, and describing this
        // fixture's departure, which has no references loaded, traps.
        #expect(pushed.tripPage.viewModel.tripConvertible.tripID == "trip_43")
    }

    /// Embedded, the page's title and its iPhone Duo refresh button belong on
    /// the host: the bar shows the host's item, and a screen pushed over the
    /// host takes its back title from the host.
    @Test func `The host carries the page's title, and its refresh button where bars are vertical`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        host.tripPage.presentsBarsVerticallyOverride = true
        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = try show(navigation)

        push(host, onto: navigation, in: window)

        #expect(host.title == "Route 49 to Downtown Seattle Broadway")
        #expect(host.navigationItem.rightBarButtonItem != nil)
        #expect(!navigation.isNavigationBarHidden)
        // Rendered against the stack, not before the host was on one.
        #expect(host.tripPage.rootView.backBehavior == .pop)
        #expect(!host.tripPage.rootView.showsBackRow)
    }

    /// The page hides the bar for the host, gives it to a screen pushed on top,
    /// and hands it back when the host is popped. Embedded, the page isn't one of
    /// the stack's controllers, so it has to ask about the host instead.
    @Test func `The embedded page hides the bar, and hands it to a screen pushed over the host`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let host = TripMapHostViewController(application: makeApplication(dataLoader: dataLoader), arrivalDeparture: try makeDeparture())
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        let window = try show(navigation)

        push(host, onto: navigation, in: window)
        #expect(navigation.isNavigationBarHidden)

        push(UIViewController(), onto: navigation, in: window)
        #expect(!navigation.isNavigationBarHidden)

        pop(navigation, in: window)
        #expect(navigation.isNavigationBarHidden)

        // The host had the bar hidden before the page hid it, so it stays hidden.
        pop(navigation, in: window)
        #expect(navigation.isNavigationBarHidden)
    }
}
