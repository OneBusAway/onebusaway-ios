//
//  RegionWideAgencyAlertTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Regression coverage for region-wide agency alerts.
///
/// Obaco (sidecar.onebusaway.org) marks alerts that apply to the whole region —
/// rather than to one specific agency — with an *empty* `agency_id` in the GTFS-RT
/// `informed_entity`. `AgencyAlert` used to reject those alerts with
/// `AlertError.unknownAgency` because no agency in the region has an empty ID, and
/// `ObacoAPIService.getAlerts` silently dropped them via `try?`. The result was that
/// high-severity region-wide alerts never reached `AgencyAlertsStore`, so the modal
/// `AgencyAlertBulletin` never appeared.
class RegionWideAgencyAlertTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
        queue.cancelAllOperations()
    }

    private let enUSLocale = Locale(identifier: "en_US")

    // MARK: - Helpers

    private func loadAgencies() throws -> [AgencyWithCoverage] {
        try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
    }

    private func translatedString(_ text: String) -> TransitRealtime_TranslatedString {
        var translation = TransitRealtime_TranslatedString.Translation()
        translation.text = text
        translation.language = "en"

        var translated = TransitRealtime_TranslatedString()
        translated.translation = [translation]
        return translated
    }

    /// Builds a feed entity mirroring the live Obaco regional alerts payload:
    /// a WARNING-severity alert whose `informed_entity` carries an empty `agency_id`.
    private func makeRegionWideFeedEntity(startDate: Date = Date()) -> TransitRealtime_FeedEntity {
        var period = TransitRealtime_TimeRange()
        period.start = UInt64(startDate.timeIntervalSince1970)
        period.end = UInt64(startDate.timeIntervalSince1970 + 28_800)

        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = ""

        var alert = TransitRealtime_Alert()
        alert.severityLevel = .warning
        alert.activePeriod = [period]
        alert.informedEntity = [entitySelector]
        alert.headerText = translatedString("Get Ready for World Cup")
        alert.descriptionText = translatedString("Transit agencies are preparing for record ridership.")
        alert.url = translatedString("https://www.example.com/worldcup")

        var feedEntity = TransitRealtime_FeedEntity()
        feedEntity.id = "Alert_1"
        feedEntity.alert = alert
        return feedEntity
    }

    private func makeFeedData(entities: [TransitRealtime_FeedEntity]) throws -> Data {
        var message = TransitRealtime_FeedMessage()
        message.header.gtfsRealtimeVersion = "1.0"
        message.entity = entities
        return try message.serializedData()
    }

    // MARK: - Model Parsing

    func test_emptyAgencyID_parsesAsRegionWideAlert() throws {
        let agencies = try loadAgencies()
        let feedEntity = makeRegionWideFeedEntity()

        let alert = try AgencyAlert(feedEntity: feedEntity, agencies: agencies)

        XCTAssertNil(alert.agency, "A region-wide alert is not affiliated with any single agency")
        XCTAssertEqual(alert.agencyID, "")
        XCTAssertTrue(alert.isHighSeverity)
        XCTAssertEqual(alert.title(forLocale: enUSLocale), "Get Ready for World Cup")
        XCTAssertEqual(alert.url(forLocale: enUSLocale)?.absoluteString, "https://www.example.com/worldcup")
    }

    func test_unknownNonEmptyAgencyID_stillThrows() throws {
        let agencies = try loadAgencies()

        var feedEntity = makeRegionWideFeedEntity()
        var entitySelector = TransitRealtime_EntitySelector()
        entitySelector.agencyID = "not-a-real-agency"
        feedEntity.alert.informedEntity = [entitySelector]

        XCTAssertThrowsError(try AgencyAlert(feedEntity: feedEntity, agencies: agencies)) { error in
            XCTAssertEqual(error as? AgencyAlert.AlertError, .unknownAgency)
        }
    }

    func test_missingAgencyID_throwsInvalidAlert() throws {
        let agencies = try loadAgencies()

        // An `informed_entity` whose `agency_id` was never set (presence bit false),
        // as distinct from one explicitly set to the empty string. This is not a
        // region-wide alert; it's malformed and must be rejected.
        var feedEntity = makeRegionWideFeedEntity()
        feedEntity.alert.informedEntity = [TransitRealtime_EntitySelector()]

        XCTAssertThrowsError(try AgencyAlert(feedEntity: feedEntity, agencies: agencies)) { error in
            XCTAssertEqual(error as? AgencyAlert.AlertError, .invalidAlert)
        }
    }

    // MARK: - Obaco Service

    func test_obacoGetAlerts_includesRegionWideAlerts() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader) // swiftlint:disable:this force_cast
        let feedData = try makeFeedData(entities: [makeRegionWideFeedEntity()])
        dataLoader.mock(data: feedData) { request in
            request.url!.absoluteString.contains("alerts.pb")
        }

        let agencies = try loadAgencies()
        let alerts = try await obacoService.getAlerts(agencies: agencies)

        XCTAssertEqual(alerts.count, 1, "The region-wide alert must not be dropped during parsing")

        let alert = try XCTUnwrap(alerts.first)
        XCTAssertNil(alert.agency)
        XCTAssertTrue(alert.isHighSeverity)
        XCTAssertEqual(alert.title(forLocale: enUSLocale), "Get Ready for World Cup")
    }

    func test_obacoGetAlerts_oneBadEntityDoesNotDropTheRest() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader) // swiftlint:disable:this force_cast

        // A feed carrying one valid region-wide alert and one malformed entity (an
        // unknown, non-empty agency ID). The bad entity must be dropped without
        // taking the valid alert down with it — the resilience the per-entity
        // `do/catch` in `getAlerts` exists to provide.
        var badEntity = makeRegionWideFeedEntity()
        badEntity.id = "Alert_Bad"
        var badSelector = TransitRealtime_EntitySelector()
        badSelector.agencyID = "not-a-real-agency"
        badEntity.alert.informedEntity = [badSelector]

        let feedData = try makeFeedData(entities: [makeRegionWideFeedEntity(), badEntity])
        dataLoader.mock(data: feedData) { request in
            request.url!.absoluteString.contains("alerts.pb")
        }

        let agencies = try loadAgencies()
        let alerts = try await obacoService.getAlerts(agencies: agencies)

        XCTAssertEqual(alerts.count, 1, "The valid alert must survive even when a sibling entity fails to parse")
        XCTAssertEqual(try XCTUnwrap(alerts.first).title(forLocale: enUSLocale), "Get Ready for World Cup")
    }

    // MARK: - Bulletin Presentation Pipeline

    /// Drives the real pipeline used at app launch — `AgencyAlertsStore.update()` through
    /// the API services — and asserts that a fresh region-wide WARNING alert lands in
    /// `recentUnreadHighSeverityAlerts`, the exact predicate `Application.agencyAlertsUpdated()`
    /// uses to decide whether to present the modal `AgencyAlertBulletin`.
    @MainActor
    func test_regionWideAlert_isSurfacedForBulletinPresentation() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let feedData = try makeFeedData(entities: [makeRegionWideFeedEntity()])
        dataLoader.mock(data: feedData) { request in
            let url = request.url!.absoluteString
            return url.contains("/api/gtfs_realtime/alerts-for-agency") || url.contains("alerts.pb")
        }

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

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
        let app = Application(config: config)
        let store = app.alertsStore

        try await store.update()

        let alert = try XCTUnwrap(
            store.recentUnreadHighSeverityAlerts.first,
            "A fresh region-wide WARNING alert must qualify for bulletin presentation"
        )
        XCTAssertNil(alert.agency)

        let bulletin = AgencyAlertBulletin(agencyAlert: alert, locale: enUSLocale)
        XCTAssertNotNil(bulletin, "The bulletin must be constructible from a region-wide alert")
    }
}
