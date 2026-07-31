//
//  StopPageActionPresenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The presenter owns every "leaves the Stop page" flow for both the pushed
/// screen and the map sheet. These tests pin down which controller each flow
/// presents, and — most importantly — that the presenter presents from the
/// controller its provider resolves rather than no-oping.
@MainActor
@Suite(.serialized)
final class StopPageActionPresenterTests: OBATestCase {

    private var queue: OperationQueue!
    private var window: UIWindow!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// A presented controller only materializes when the presenter is in a
    /// window, so every test roots one.
    private func makeHost() -> UIViewController {
        let host = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        return host
    }

    private func makePresenter(host: UIViewController) -> (StopPageActionPresenter, Application) {
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let presenter = StopPageActionPresenter(
            application: application,
            presentingController: { host }
        )
        return (presenter, application)
    }

    private func stubScheduleForStop(dataLoader: MockDataLoader) {
        // Match any schedule-for-stop path and return fixture data (ignore query params and stop ID)
        let scheduleData = Fixtures.loadData(file: "schedule-for-stop_1_75403.json")
        dataLoader.mock(data: scheduleData) { request in
            guard let path = request.url?.path else { return false }
            return path.contains("/schedule-for-stop/") && path.hasSuffix(".json")
        }
    }

    private func stubArrivalsAndDepartures(dataLoader: MockDataLoader) {
        // Use mock(url:with:) which ignores query parameters (only matches host + path)
        dataLoader.mock(
            url: URL(string: "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/1_10914.json")!,
            with: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        )
    }

    /// Helper to create a valid ArrivalDeparture with route data (Fixtures.arrivalDeparture() is incomplete)
    private func makeDepartureWithRoute() throws -> ArrivalDeparture {
        // Load fixture directly from file and extract first arrival
        let data = Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let responseData = json?["data"] as? [String: Any]
        let entry = responseData?["entry"] as? [String: Any]
        let arrivalsArray = entry?["arrivalsAndDepartures"] as? [[String: Any]]
        guard let firstArrivalDict = arrivalsArray?.first else {
            throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No departures in fixture"])
        }
        let arrivalData = try JSONSerialization.data(withJSONObject: firstArrivalDict)
        let departure = try JSONDecoder().decode(ArrivalDeparture.self, from: arrivalData)
        return departure
    }

    /// `present` is asynchronous; poll briefly rather than assuming one runloop
    /// turn is enough.
    private func waitForPresentation(on controller: UIViewController) async -> UIViewController? {
        for _ in 0..<20 {
            if let presented = controller.presentedViewController { return presented }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return controller.presentedViewController
    }

    @Test func `Schedule for stop presents the schedule controller`() async {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)

        presenter.showScheduleForStop(stopID: "1_10914")

        let presented = await waitForPresentation(on: host)
        #expect(presented is ScheduleForStopViewController)
    }

    @Test func `Stop level bookmark presents the add bookmark controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let stop = try #require(Fixtures.loadSomeStops().first)

        presenter.showBookmarkEditor(for: nil, stop: stop, preloadedArrivals: nil)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is AddBookmarkViewController)
    }

    @Test func `Departure level bookmark presents the edit bookmark controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let departure = try makeDepartureWithRoute()

        presenter.showBookmarkEditor(for: departure, stop: nil, preloadedArrivals: nil)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is EditBookmarkViewController)
    }

    @Test func `Report a problem presents the report controller`() async throws {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)
        let stop = try #require(Fixtures.loadSomeStops().first)

        presenter.showReportProblem(stop: stop)

        let presented = await waitForPresentation(on: host)
        let navigation = try #require(presented as? UINavigationController)
        #expect(navigation.viewControllers.first is ReportProblemViewController)
    }

    @Test func `External survey error presents an alert`() async {
        let host = makeHost()
        let (presenter, _) = makePresenter(host: host)

        presenter.showExternalSurveyError()

        let presented = await waitForPresentation(on: host)
        #expect(presented is UIAlertController)
    }

    /// The reason the presenting-controller provider exists. UIKit ignores
    /// `present` on a controller that already has a `presentedViewController`,
    /// and in the sheet system the host always does — so a provider that
    /// returns the topmost controller must be honoured, or the modal silently
    /// never appears.
    @Test func `Presenting resolves the provider at call time not at init`() async {
        let host = makeHost()
        let dataLoader = MockDataLoader(testName: name)
        stubScheduleForStop(dataLoader: dataLoader)
        stubArrivalsAndDepartures(dataLoader: dataLoader)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        // The provider starts pointing at `host`, then moves to a modal that
        // gets presented afterwards — exactly the sheet-stack shape.
        var target: UIViewController = host
        let presenter = StopPageActionPresenter(
            application: application,
            presentingController: { target }
        )

        let modal = UIViewController()
        host.present(modal, animated: false)
        _ = await waitForPresentation(on: host)
        target = modal

        presenter.showScheduleForStop(stopID: "1_10914")

        let presented = await waitForPresentation(on: modal)
        #expect(presented is ScheduleForStopViewController)
        #expect(host.presentedViewController === modal)
    }
}
