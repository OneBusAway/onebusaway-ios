//
//  AgencyAlertListViewConvertersTests.swift
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

@MainActor
@Suite(.serialized)
final class AgencyAlertListViewConvertersTests: OBATestCase {

    var queue: OperationQueue!
    var app: Application!
    var mockController: MockAlertConverterController!

    final class MockAlertConverterController: UIViewController, AgencyAlertListViewConverters {
        let application: Application
        var presentedAlerts: [TransitAlertDataListViewModel] = []

        init(application: Application) {
            self.application = application
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func presentAlert(_ alert: TransitAlertDataListViewModel) {
            presentedAlerts.append(alert)
        }
    }

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let dataLoader = MockDataLoader(testName: name)
        app = buildApplication(queue: queue, dataLoader: dataLoader)
        mockController = MockAlertConverterController(application: app)
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func makeAgencyAlert(
        id: String,
        title: String,
        agencyName: String? = nil,
        body: String = "",
        urlString: String? = nil
    ) throws -> AgencyAlert {
        let agencies = try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let matchedAgency = agencies.first { $0.agency.name == agencyName }

        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = matchedAgency?.agencyID ?? ""

        var titleTranslation = TransitRealtime_TranslatedString.Translation()
        titleTranslation.language = "en"
        titleTranslation.text = title

        var bodyTranslation = TransitRealtime_TranslatedString.Translation()
        bodyTranslation.language = "en"
        bodyTranslation.text = body

        var transitAlert = TransitRealtime_Alert()
        transitAlert.informedEntity = [entitySelector]
        transitAlert.headerText.translation = [titleTranslation]
        transitAlert.descriptionText.translation = [bodyTranslation]

        if let urlString {
            var urlTranslation = TransitRealtime_TranslatedString.Translation()
            urlTranslation.language = "en"
            urlTranslation.text = urlString
            transitAlert.url.translation = [urlTranslation]
        }

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = id
        feedEntity.alert = transitAlert

        return try AgencyAlert(feedEntity: feedEntity, agency: matchedAgency)
    }

    private func loadServiceAlert() throws -> ServiceAlert {
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        return try #require(response.references?.serviceAlerts.first)
    }

    // MARK: - listSections(agencyAlerts:) Tests

    @Test func testListSectionsGroupsByAgencyAndSortsSections() throws {
        let alertKCM1 = try makeAgencyAlert(id: "1", title: "Route 44 Detour", agencyName: "Metro Transit")
        let alertKCM2 = try makeAgencyAlert(id: "2", title: "Route 48 Reroute", agencyName: "Metro Transit")
        let alertST = try makeAgencyAlert(id: "3", title: "Link Light Rail Delay", agencyName: "Sound Transit")
        let alertRegionWide = try makeAgencyAlert(id: "4", title: "Snow Route Activation", agencyName: nil)

        let sections = mockController.listSections(agencyAlerts: [alertKCM2, alertST, alertRegionWide, alertKCM1])

        #expect(sections.count == 3)

        // Sections are sorted by section ID: "agency_alerts_", "agency_alerts_Metro Transit", "agency_alerts_Sound Transit"
        #expect(sections[0].id == "agency_alerts_")
        #expect(sections[0].title == "")
        #expect(sections[0].contents.count == 1)

        #expect(sections[1].id == "agency_alerts_Metro Transit")
        #expect(sections[1].title == "Metro Transit")
        #expect(sections[1].contents.count == 2)

        // Contents within a section are sorted by title: Route 44 comes before Route 48
        let kcmItem1 = sections[1].contents[0].as(TransitAlertDataListViewModel.self)
        let kcmItem2 = sections[1].contents[1].as(TransitAlertDataListViewModel.self)
        #expect(kcmItem1?.title == "Route 44 Detour")
        #expect(kcmItem2?.title == "Route 48 Reroute")

        #expect(sections[2].id == "agency_alerts_Sound Transit")
        #expect(sections[2].title == "Sound Transit")
        #expect(sections[2].contents.count == 1)
    }

    @Test func testListSectionsOnSelectActionTriggersPresentAlert() throws {
        let alert = try makeAgencyAlert(id: "alert_tap", title: "Tap Me", agencyName: "Metro Transit")
        let sections = mockController.listSections(agencyAlerts: [alert])

        #expect(sections.count == 1)
        guard let item = sections[0].contents.first?.as(TransitAlertDataListViewModel.self) else {
            Issue.record("Expected TransitAlertDataListViewModel item")
            return
        }

        #expect(mockController.presentedAlerts.isEmpty)
        item.onSelectAction?(item)
        #expect(mockController.presentedAlerts.count == 1)
        #expect(mockController.presentedAlerts.first?.title == "Tap Me")
    }

    // MARK: - listSection(serviceAlerts:showSectionTitle:sectionID:) Tests

    @Test func testListSectionMultipleServiceAlertsDisplaysCountInTitle() throws {
        let alert1 = try loadServiceAlert()
        let alert2 = try loadServiceAlert()

        let section = mockController.listSection(
            serviceAlerts: [alert1, alert2],
            showSectionTitle: true,
            sectionID: "custom_service_alerts"
        )

        #expect(section.id == "custom_service_alerts")
        #expect(section.hasHeader == true)
        #expect(section.title == "\(Strings.serviceAlerts) (2)")
        #expect(section.contents.count == 2)
    }

    @Test func testListSectionSingleServiceAlertDisplaysSingularTitle() throws {
        let alert = try loadServiceAlert()

        let section = mockController.listSection(
            serviceAlerts: [alert],
            showSectionTitle: true
        )

        #expect(section.id == "service_alerts")
        #expect(section.hasHeader == true)
        #expect(section.title == Strings.serviceAlert)
        #expect(section.contents.count == 1)
    }

    @Test func testListSectionWithoutSectionTitleHidesHeader() throws {
        let alert = try loadServiceAlert()

        let section = mockController.listSection(
            serviceAlerts: [alert],
            showSectionTitle: false
        )

        #expect(section.hasHeader == false)
        #expect(section.title == nil)
        #expect(section.contents.count == 1)
    }

    @Test func testListSectionOnSelectActionTriggersPresentAlert() throws {
        let alert = try loadServiceAlert()
        let section = mockController.listSection(
            serviceAlerts: [alert],
            showSectionTitle: true
        )

        guard let item = section.contents.first?.as(TransitAlertDataListViewModel.self) else {
            Issue.record("Expected TransitAlertDataListViewModel item in service alert section")
            return
        }

        #expect(mockController.presentedAlerts.isEmpty)
        item.onSelectAction?(item)
        #expect(mockController.presentedAlerts.count == 1)
    }
}
