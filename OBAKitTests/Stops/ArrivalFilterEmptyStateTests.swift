//
//  ArrivalFilterEmptyStateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@testable import OBAKit
@testable import OBAKitCore
import Foundation
import Testing
import UIKit

/// When the Departure Type filter hides every departure, the stop page shows an
/// explanatory empty state — but it must not take Load More down with it. Load
/// More is the only control that can resolve this particular empty state, since
/// widening the time window is how a real-time departure surfaces at a stop whose
/// loaded window holds nothing but scheduled ones.
@MainActor
@Suite(.serialized)
final class ArrivalFilterEmptyStateTests: OBATestCase {

    /// Every departure in this fixture is scheduled — zero `predicted` entries —
    /// so `.estimatedOnly` reliably empties the list while the unfiltered list
    /// stays populated. That is exactly the branch under test.
    private let stopID = "1_10020"

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    /// `MockDataLoader` fatal-errors on any unstubbed request, so every endpoint the
    /// stop page touches on load has to be mocked here — arrivals, surveys, and
    /// agency alerts, on top of the regions/agencies pair `buildApplication` adds.
    private func makeApplication() -> Application {
        let dataLoader = MockDataLoader(testName: name)

        dataLoader.mock(data: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020_no_realtime.json")) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }

        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        return buildApplication(queue: queue, dataLoader: dataLoader)
    }

    /// Builds the legacy stop page with `filter` already applied. The filter has to
    /// be set before the controller exists: its view model seeds the value at init.
    private func loadedController(filter: ArrivalDepartureFilter) async -> StopViewController {
        let application = makeApplication()
        application.setArrivalDepartureFilter(filter)

        let controller = StopViewController(application: application, stopID: stopID)
        controller.loadViewIfNeeded()
        await controller.viewModel.refresh()

        return controller
    }

    private func sectionIDs(of controller: StopViewController) -> [String] {
        controller.items(for: OBAListView()).map(\.id)
    }

    // MARK: - Tests

    /// The regression: the empty state used to *replace* the trailing section
    /// rather than accompany it, silently removing Load More.
    @Test func `Filtered-empty stop keeps its Load More section`() async {
        let controller = await loadedController(filter: .estimatedOnly)
        let ids = sectionIDs(of: controller)

        #expect(ids.contains(StopViewController.ListSections.emptyData.sectionID))
        #expect(ids.contains(StopViewController.ListSections.arrivalDepartures(suffix: "all").sectionID))
    }

    /// Guards the fixture's own premise. If the data ever gains a real-time
    /// departure, the test above would pass for the wrong reason — the list would
    /// never have been emptied by the filter at all.
    @Test func `Unfiltered stop shows departures and no empty state`() async {
        let controller = await loadedController(filter: .all)
        let ids = sectionIDs(of: controller)

        #expect(!ids.contains(StopViewController.ListSections.emptyData.sectionID))
        #expect(ids.contains(StopViewController.ListSections.arrivalDepartures(suffix: "all").sectionID))
    }
}
