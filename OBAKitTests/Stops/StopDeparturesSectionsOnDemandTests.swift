//
//  StopDeparturesSectionsOnDemandTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The stop page's on-demand card, on both surfaces: the SwiftUI section and its
/// navigation plumbing, and the legacy `StopViewController`'s list section.
@MainActor
@Suite(.serialized)
final class StopDeparturesSectionsOnDemandTests: OBATestCase {

    nonisolated private static let alexandriaServiceID = "5088_77652"

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private func alexandria() throws -> OnDemandService {
        try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json")).entry
    }

    // MARK: - SwiftUI

    @Test func `Section exposes one row per service and forwards selection`() throws {
        let service = try alexandria()
        var selected: OnDemandService?
        let section = OnDemandServicesSection(services: [service], onSelect: { selected = $0 })

        #expect(section.rows.map(\.id) == [Self.alexandriaServiceID])
        #expect(section.rows[0].title == "DOT Paratransit")
        #expect(section.rows[0].subtitle == Strings.onDemandKindTitle(.zone))
        section.select(section.rows[0])
        #expect(selected?.id == Self.alexandriaServiceID)
    }

    @Test func `Navigation handler carries the on-demand callback`() throws {
        var shown: OnDemandService?
        let handler = StopPageNavigationHandler(
            showTrip: { _ in }, showScheduleForStop: {}, showScheduleForRoute: { _ in }, canScheduleForRoute: true,
            showWalkingDirections: {}, showDirectionsToHere: nil, showDirectionsFromHere: nil,
            showAlertDetail: { _ in }, showOnDemandService: { shown = $0 },
            showBookmarkEditor: { _ in }, shareTrip: { _ in }, showAlarmPicker: { _ in }, startLiveActivity: { _ in },
            showExternalSurveyError: {}, showDonation: {}, dismissDonation: { _ in },
            makeTripPreview: { _ in AnyView(EmptyView()) },
            showRouteFilter: {}, showServiceAlerts: {}, showNearbyStops: {}, showReportProblem: {}, closeSheet: {}
        )
        let service = try alexandria()
        handler.showOnDemandService(service)
        #expect(shown?.id == Self.alexandriaServiceID)
    }

    // MARK: - Legacy StopViewController

    /// `MockDataLoader` fatal-errors on an unstubbed URL, so the service behind
    /// every pointer is stubbed alongside arrivals, surveys and agency alerts.
    /// The arrivals fixture is empty: a flex-only stop has pointers and nothing
    /// scheduled, and the card must still show.
    private func loadedController(onDemandServiceIDs: [String]) async throws -> StopViewController {
        let dataLoader = MockDataLoader(testName: name)
        let arrivals = try Fixtures.loadData(file: "arrivals_and_departures_empty.json", stampingOnDemandServiceIDs: onDemandServiceIDs)
        dataLoader.mock(data: arrivals) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_service_alexandria.json")) {
            $0.url?.path.contains("/api/ondemand/service/\(Self.alexandriaServiceID)") ?? false
        }
        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { $0.url?.path.contains("/surveys.json") ?? false }
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let controller = StopViewController(application: application, stopID: "1_TEST")
        controller.loadViewIfNeeded()
        await controller.viewModel.refresh()
        await controller.viewModel.onDemandFetchTask?.value
        return controller
    }

    private func onDemandSection(of controller: StopViewController) -> OBAListViewSection? {
        controller.items(for: OBAListView()).first { $0.id == StopViewController.ListSections.onDemandServices.sectionID }
    }

    @Test func `Legacy page lists a flex-only stop's services under the on-demand title`() async throws {
        let controller = try await loadedController(onDemandServiceIDs: [Self.alexandriaServiceID])

        let section = try #require(onDemandSection(of: controller))
        #expect(section.title == Strings.onDemandSectionTitle)
        let row = try #require(section.contents.first?.as(OBAListRowView.SubtitleViewModel.self))
        #expect(section.contents.count == 1)
        #expect(row.title == .string("DOT Paratransit"))
        #expect(row.subtitle == .string(Strings.onDemandKindTitle(.zone)))
    }

    @Test func `Legacy page has no on-demand section for a stop without pointers`() async throws {
        let controller = try await loadedController(onDemandServiceIDs: [])
        #expect(onDemandSection(of: controller) == nil)
    }

    @Test func `Selecting a legacy row pushes the service page`() async throws {
        let controller = try await loadedController(onDemandServiceIDs: [Self.alexandriaServiceID])
        let navigation = UINavigationController(rootViewController: controller)

        let row = try #require(onDemandSection(of: controller)?.contents.first)
        row.onSelectAction?(row)

        #expect(navigation.topViewController is OnDemandServiceViewController)
    }
}
