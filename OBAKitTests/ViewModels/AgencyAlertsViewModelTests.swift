//
//  AgencyAlertsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import Combine
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `AgencyAlertsViewModel`. Covers `isLoading` flag transitions,
/// `collapsedSections` round-trip, error-delegate handling, both branches of
/// `shareActivityItems(for:)`, and deduplication via `dedupedAlerts()`.
@Suite(.serialized)
final class AgencyAlertsViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Builds a region-wide `AgencyAlert` (no agency, empty agencyID).
    /// Accepting an explicit `id` lets callers create two alerts that share the
    /// same id but differ in proto content, so both survive `Set<AgencyAlert>`
    /// insertion while `dedupedAlerts()` still collapses them to one.
    private func makeAgencyAlert(
        id: String,
        title: String,
        body: String = "",
        urlString: String? = nil
    ) throws -> AgencyAlert {
        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

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

        return try AgencyAlert(feedEntity: feedEntity, agency: nil)
    }

    /// Wraps `makeAgencyAlert` in a `TransitAlertDataListViewModel` for use in
    /// `shareActivityItems` assertions. Uses a UUID-based id so each call is unique.
    private func makeAlertVM(
        title: String,
        body: String,
        urlString: String? = nil
    ) throws -> TransitAlertDataListViewModel {
        let alert = try makeAgencyAlert(
            id: "share-test-\(UUID().uuidString)",
            title: title,
            body: body,
            urlString: urlString
        )
        return TransitAlertDataListViewModel(alert, forLocale: Locale(identifier: "en"))
    }

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - Tests

    @Test @MainActor
    func `Init empty alerts and not loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)

        #expect(viewModel.alerts.isEmpty)
        #expect(!viewModel.isLoading)
        #expect(viewModel.collapsedSections.isEmpty)
    }

    @Test @MainActor
    func `Reload server data sets is loading true`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()

        #expect(viewModel.isLoading)
    }

    @Test @MainActor
    func `Agency alerts updated clears is loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Collapsed sections survives refresh`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.collapsedSections = ["agency_1", "agency_2"]

        // Simulate a store-driven refresh cycle.
        viewModel.reloadServerData()
        viewModel.agencyAlertsUpdated()

        #expect(viewModel.collapsedSections == ["agency_1", "agency_2"])
    }

    @Test @MainActor
    func `Display error clears is loading`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = AgencyAlertsViewModel(application: app)
        viewModel.reloadServerData()
        viewModel.agencyAlertsStore(app.alertsStore, displayError: URLError(.badServerResponse))

        #expect(!viewModel.isLoading)
    }

    @Test @MainActor
    func `Share activity items with URL returns URL`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = AgencyAlertsViewModel(application: app)

        let alertVM = try makeAlertVM(
            title: "Service Disruption",
            body: "Buses delayed due to traffic.",
            urlString: "https://alerts.example.com/1"
        )

        let items = viewModel.shareActivityItems(for: alertVM)

        #expect(items.count == 1)
        #expect(items.first as? URL == URL(string: "https://alerts.example.com/1"))
    }

    @Test @MainActor
    func `Deduped alerts collapses alerts with same ID`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = AgencyAlertsViewModel(application: app)

        // Two alerts share the same id string but differ in proto content (title).
        // AgencyAlert equality uses full proto content, so both occupy distinct
        // slots in the store's Set<AgencyAlert>.
        let sharedID = "dedup-test-alert"
        let alertA = try makeAgencyAlert(id: sharedID, title: "Version A")
        let alertB = try makeAgencyAlert(id: sharedID, title: "Version B")

        app.alertsStore.insertAlerts([alertA, alertB])

        // Pre-condition: the store holds both objects. If this is 1, the Set
        // already deduplicated by content and dedupedAlerts() has nothing to do.
        #expect(app.alertsStore.agencyAlerts.count == 2)

        // agencyAlertsUpdated() is the only caller of dedupedAlerts().
        viewModel.agencyAlertsUpdated()

        #expect(viewModel.alerts.count == 1)
        #expect(viewModel.alerts.first?.id == sharedID)
    }

    @Test @MainActor
    func `Share activity items without URL returns title and body`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = AgencyAlertsViewModel(application: app)

        let alertVM = try makeAlertVM(
            title: "Service Disruption",
            body: "Buses delayed due to traffic."
        )

        let items = viewModel.shareActivityItems(for: alertVM)

        #expect(items.count == 2)
        #expect(items[0] as? String == "Service Disruption")
        #expect(items[1] as? String == "Buses delayed due to traffic.")
    }
}
