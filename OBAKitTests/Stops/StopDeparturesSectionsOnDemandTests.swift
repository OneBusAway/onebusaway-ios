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
@testable import OBAKit
@testable import OBAKitCore

/// The stop page's on-demand card: the SwiftUI section and its navigation
/// plumbing.
@MainActor
@Suite(.serialized)
final class StopDeparturesSectionsOnDemandTests: OBATestCase {

    nonisolated private static let alexandriaServiceID = "5088_77652"

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
        section.select(section.rows[0])
        #expect(selected?.id == Self.alexandriaServiceID)
    }

    @Test func `Navigation handler carries the on-demand callback`() throws {
        var shown: OnDemandService?
        let handler = StopPageNavigationHandler(
            showTrip: { _ in }, showScheduleForStop: {}, showScheduleForRoute: { _ in },
            showWalkingDirections: {}, pillDirections: .none,
            showDirectionsToHere: nil, showDirectionsFromHere: nil,
            showAlertDetail: { _ in }, showOnDemandService: { shown = $0 },
            showBookmarkEditor: { _ in }, shareTrip: { _ in }, showAlarmPicker: { _ in }, startLiveActivity: { _ in },
            showExternalSurveyError: {}, showDonation: {}, dismissDonation: { _ in },
            makeTripPreview: { _ in AnyView(EmptyView()) },
            showRouteFilter: {}, showServiceAlerts: {}, showNearbyStops: {}, showReportProblem: {}, toggleProximityAlert: {}, closeSheet: {}
        )
        let service = try alexandria()
        handler.showOnDemandService(service)
        #expect(shown?.id == Self.alexandriaServiceID)
    }
}
