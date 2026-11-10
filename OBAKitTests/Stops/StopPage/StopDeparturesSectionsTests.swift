//
//  StopDeparturesSectionsTests.swift
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

/// What a hosted `List` of `StopDeparturesSections` shows.
private struct HostedList {
    /// Row count of each section, top to bottom.
    var rowsPerSection: [Int] = []
    /// Sections holding a row whose view tree contains a `SurveyCell`.
    var surveySections: [Int] = []
    /// Sections holding a row whose view tree contains a `DonationCell`.
    var donationSections: [Int] = []
    /// Spinners anywhere in the list. The loading row's `ProgressView` is one.
    var spinnerCount = 0
}

/// Tests for `StopDeparturesSections`, the sections both stop page
/// presentations put in their `List`. The view is hosted in a real window, and
/// the assertions read the `UICollectionView` that backs the `List`: how many
/// sections and rows it has, and where the survey and donation cards (UIKit
/// cells) landed. The on-demand card is covered in
/// `StopDeparturesSectionsOnDemandTests`.
@MainActor
@Suite(.serialized)
final class StopDeparturesSectionsTests: OBATestCase {

    // MARK: - Fixtures

    private func survey() -> Survey {
        Survey(
            id: 42,
            name: "Rider survey",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: false,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            alwaysVisible: false,
            study: Study(id: 1, name: "Study", description: "A study"),
            questions: [
                SurveyQuestion(id: 1, position: 1, required: true, content: QuestionContent(labelText: "How was your trip?", type: .radio, options: ["Good", "Bad"], url: nil))
            ]
        )
    }

    private func serviceAlert() throws -> ServiceAlert {
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        return try #require(response.references?.serviceAlerts.first)
    }

    /// `arrivals_and_departures_for_stop_1_10020.json` (four departures on two
    /// routes), moved so the earliest leaves five minutes from now. Its own
    /// times are from 2012, and route mode drops past departures.
    private func upcomingDepartures() throws -> [ArrivalDeparture] {
        let raw = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "arrivals_and_departures_for_stop_1_10020.json"))
        var json = try #require(raw as? [String: Any])
        var data = try #require(json["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        let list = try #require(entry["arrivalsAndDepartures"] as? [[String: Any]])

        let earliest = try #require(list.compactMap { $0["scheduledDepartureTime"] as? Int64 }.min())
        let shift = Int64(Date().timeIntervalSince1970 * 1000) + 5 * 60_000 - earliest
        let timeKeys = ["scheduledArrivalTime", "scheduledDepartureTime", "predictedArrivalTime", "predictedDepartureTime", "lastUpdateTime", "serviceDate"]
        entry["arrivalsAndDepartures"] = list.map { departure in
            var departure = departure
            for key in timeKeys {
                // Zero means "no prediction" and has to stay zero.
                if let time = departure[key] as? Int64, time != 0 { departure[key] = time + shift }
            }
            return departure
        }
        data["entry"] = entry
        json["data"] = data

        let shifted = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<StopArrivals>.self, from: shifted).entry.arrivalsAndDepartures
    }

    // MARK: - Builders

    private func content(
        departures: [ArrivalDeparture] = [],
        sortType: StopSort = .time,
        hasLoadedArrivals: Bool = true,
        isLoading: Bool = false
    ) -> StopPageContent {
        var preferences = StopPreferences()
        preferences.sortType = sortType
        return StopPageContent(
            stop: nil,
            allDepartures: departures,
            hasLoadedArrivals: hasLoadedArrivals,
            preferences: preferences,
            isListFiltered: false,
            arrivalDepartureFilter: .all,
            isLoading: isLoading,
            hasError: false,
            isBrokenBookmark: false
        )
    }

    private func sections(
        _ content: StopPageContent,
        survey: Survey? = nil,
        serviceAlerts: [ServiceAlert] = [],
        showsDonation: Bool = false
    ) -> StopDeparturesSections {
        StopDeparturesSections(
            content: content,
            survey: survey,
            stopID: "1_10020",
            serviceAlerts: serviceAlerts,
            onDemandServices: [],
            sortType: content.isGrouped ? .route : .time,
            walkMinutes: nil,
            minutesAfter: 30,
            isBrokenBookmark: false,
            errorText: nil,
            showsDonation: showsDonation,
            isLoadMoreExhausted: false,
            isLoading: false,
            pastCollapsed: false,
            expandedRouteID: nil,
            highlightedTripID: nil,
            statusProvider: { DepartureStatus(arrivalDeparture: $0) },
            alarmLookup: { _ in nil },
            alarmLeadTime: { _ in 10 },
            canAlarm: { _ in false },
            actionsProvider: { _ in
                DepartureRowActions(canAlarm: false, hasAlarm: false, onAlarmToggle: {}, onSchedule: {}, onBookmark: {}, onShowTrip: {}, onShareTrip: {}, makePreview: { AnyView(EmptyView()) })
            },
            onSurveyNext: { _ in }, onSurveyDismiss: {}, onSurveyExternal: {},
            onDonate: {}, onDonationClose: {},
            onSelectAlert: { _ in }, onSelectOnDemandService: { _ in },
            onChangeMode: { _ in }, onTogglePast: {}, onToggleRoute: { _ in },
            onSelectDeparture: { _ in }, onAlarmToggle: { _ in },
            onRetry: {}, onShowAllRoutes: {}, onShowAllDepartureTypes: {}, onLoadMore: {}
        )
    }

    /// Hosts `view` in a `List` in a window tall enough to realize every row.
    private func host(_ view: StopDeparturesSections) throws -> HostedList {
        let controller = UIHostingController(rootView: List { view })
        let window = UIWindow(windowScene: try testWindowScene())
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 2400)
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.layoutIfNeeded()
        // One run-loop pass so List cells finish their first layout.
        RunLoop.main.run(until: Date())

        func descendants(of view: UIView) -> [UIView] {
            view.subviews + view.subviews.flatMap(descendants(of:))
        }
        let collectionView = try #require(descendants(of: controller.view).lazy.compactMap { $0 as? UICollectionView }.first)
        collectionView.layoutIfNeeded()

        var list = HostedList()
        list.rowsPerSection = (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        // Every row realized, so a card or spinner reported absent really is absent,
        // rather than not built yet.
        try #require(!list.rowsPerSection.isEmpty)
        try #require(collectionView.visibleCells.count == list.rowsPerSection.reduce(0, +))
        list.spinnerCount = descendants(of: controller.view).filter { $0 is UIActivityIndicatorView }.count
        for cell in collectionView.visibleCells {
            guard let section = collectionView.indexPath(for: cell)?.section else { continue }
            let cellViews = descendants(of: cell)
            if cellViews.contains(where: { $0 is SurveyCell }) { list.surveySections.append(section) }
            if cellViews.contains(where: { $0 is DonationCell }) { list.donationSections.append(section) }
        }
        return list
    }

    // MARK: - Cards

    @Test func `Survey card shows only when there is a survey, at the top`() throws {
        #expect(try host(sections(content())).surveySections.isEmpty)

        let list = try host(sections(content(), survey: survey()))

        #expect(list.surveySections == [0])
    }

    @Test func `Donation card shows only when asked for, below the survey`() throws {
        #expect(try host(sections(content(), survey: survey())).donationSections.isEmpty)

        let list = try host(sections(content(), survey: survey(), showsDonation: true))

        #expect(list.surveySections == [0])
        #expect(list.donationSections == [1])
    }

    @Test func `Service alerts add a section of their own`() throws {
        let withoutAlerts = try host(sections(content()))

        let withAlerts = try host(sections(content(), serviceAlerts: [serviceAlert()]))

        #expect(withAlerts.rowsPerSection.count == withoutAlerts.rowsPerSection.count + 1)
    }

    // MARK: - Loading and empty

    @Test func `Before arrivals first load, the loading row is all that shows`() throws {
        let list = try host(sections(content(hasLoadedArrivals: false, isLoading: true)))

        #expect(list.rowsPerSection == [1])
        #expect(list.spinnerCount == 1)
    }

    /// The header and footer stay, but the middle row is the spinner, not
    /// "No departures", while a refresh is still in flight.
    @Test func `A refresh with nothing yet to show keeps the loading row`() throws {
        let list = try host(sections(content(isLoading: true)))

        #expect(list.rowsPerSection == [1, 1, 1])
        #expect(list.spinnerCount == 1)
    }

    @Test func `A loaded stop with no departures shows the empty state between the header and footer`() throws {
        let list = try host(sections(content()))

        #expect(list.rowsPerSection == [1, 1, 1])
        #expect(list.spinnerCount == 0)
    }

    // MARK: - Departures

    @Test func `Time mode lists each departure on its own row`() throws {
        let departures = try upcomingDepartures()
        #expect(departures.count == 4)

        let list = try host(sections(content(departures: departures, sortType: .time)))

        #expect(list.rowsPerSection == [1, 4, 1])
    }

    /// `GroupedListView` makes each route a section of its own (the section is
    /// the route's card), collapsed to one row while no route is expanded.
    @Test func `Route mode gives each route its own card`() throws {
        let departures = try upcomingDepartures()
        #expect(Set(departures.map(\.routeID)).count == 2)

        let list = try host(sections(content(departures: departures, sortType: .route)))

        #expect(list.rowsPerSection == [1, 1, 1, 1])
    }
}
