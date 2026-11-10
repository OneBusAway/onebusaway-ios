//
//  ContactUsHelperTests.swift
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

/// Tests for `ContactUsHelper`, which builds the feedback emails sent to the app
/// developers and to the rider's transit agency. The debug list also carries the
/// OS version, device model and locale; those vary by machine, so no test asserts
/// on them.
@MainActor
@Suite(.serialized)
final class ContactUsHelperTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Puget Sound, from `buildApplication`'s fixed region.
    private func applicationWithRegion() -> Application {
        buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
    }

    /// No fixed region, no stored selection and no location, so nothing selects one.
    private func applicationWithoutRegion() -> Application {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock()),
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            onDemandSupport: OnDemandSupport()
        )
        return Application(config: config)
    }

    /// One `<li>` of the developer email's debug list, as the template renders it.
    private func debugLine(_ label: String, _ value: String) -> String {
        "<li>\(label) = <strong>\(value)</strong></li>"
    }

    // MARK: - Developer email

    @Test func `Developer email lists the current region's name, ID and API URL`() throws {
        let application = applicationWithRegion()
        let region = try #require(application.currentRegion)
        #expect(region.name == "Puget Sound")

        let body = ContactUsHelper(application: application).appDevelopersMessageTemplate

        #expect(body.contains(debugLine("Region", "Puget Sound")))
        #expect(body.contains(debugLine("Region ID", String(region.regionIdentifier))))
        #expect(body.contains(debugLine("Base API URL", region.OBABaseURL.absoluteString)))
        #expect(body.contains("No Region Selected") == false)
    }

    @Test func `Developer email says no region is selected when there isn't one`() {
        let application = applicationWithoutRegion()
        #expect(application.currentRegion == nil)

        let body = ContactUsHelper(application: application).appDevelopersMessageTemplate

        #expect(body.contains(debugLine("Region", "No Region Selected")))
        #expect(body.contains("Region ID =") == false)
        #expect(body.contains("Base API URL =") == false)
    }

    @Test func `Developer email reports how many bookmarks the rider has`() throws {
        let application = applicationWithRegion()
        let helper = ContactUsHelper(application: application)
        let stops = try Fixtures.loadSomeStops()
        #expect(helper.appDevelopersMessageTemplate.contains(debugLine("Bookmark Count", "0")))

        application.userDataStore.add(Bookmark(name: "Home", regionIdentifier: 1, stop: stops[0]), to: nil)
        application.userDataStore.add(Bookmark(name: "Work", regionIdentifier: 1, stop: stops[1]), to: nil)
        #expect(application.userDataStore.bookmarks.count == 2)

        #expect(helper.appDevelopersMessageTemplate.contains(debugLine("Bookmark Count", "2")))
    }

    /// `buildApplication`'s location manager reports `TestData.mockSeattleLocation`
    /// once updates start.
    @Test func `Developer email shows the rider's coordinates when known`() throws {
        let application = applicationWithRegion()
        application.locationService.startUpdates()
        #expect(application.locationService.currentLocation != nil)

        let body = ContactUsHelper(application: application).appDevelopersMessageTemplate

        #expect(body.contains(debugLine("Current Location", "(47.623651,-122.312572)")))
    }

    @Test func `Developer email shows N/A without a location`() {
        let application = applicationWithoutRegion()
        #expect(application.locationService.currentLocation == nil)

        let body = ContactUsHelper(application: application).appDevelopersMessageTemplate

        #expect(body.contains(debugLine("Current Location", "N/A")))
    }

    // MARK: - Agency email

    @Test func `Agency email goes to the region's contact address`() throws {
        let application = applicationWithRegion()
        let contactEmail = try #require(application.currentRegion?.contactEmail)
        #expect(contactEmail != "contact@onebusaway.org")

        #expect(ContactUsHelper(application: application).transitAgencyEmail == contactEmail)
    }

    @Test func `Agency email falls back to the OneBusAway address without a region`() {
        let application = applicationWithoutRegion()
        #expect(application.currentRegion == nil)

        #expect(ContactUsHelper(application: application).transitAgencyEmail == "contact@onebusaway.org")
    }

    // MARK: - Can't send email

    @Test func `Can't-send alert gives the agency address for the agency and the developer address for developers`() throws {
        let application = applicationWithRegion()
        let agencyEmail = try #require(application.currentRegion?.contactEmail)
        let developerEmail = ContactUsHelper.appDevelopersEmail
        // Distinct, or swapping the two targets would go unnoticed.
        #expect(agencyEmail != developerEmail)
        let helper = ContactUsHelper(application: application)

        let agencyMessage = try #require(helper.buildCantSendEmailAlert(target: .transitAgency).message)
        #expect(agencyMessage.contains(agencyEmail))
        #expect(agencyMessage.contains(developerEmail) == false)

        let developerAlert = helper.buildCantSendEmailAlert(target: .appDevelopers)
        let developerMessage = try #require(developerAlert.message)
        #expect(developerMessage.contains(developerEmail))
        #expect(developerMessage.contains(agencyEmail) == false)

        // Copy Email Address, Copy Debug Info, then Cancel.
        #expect(developerAlert.actions.map(\.style) == [.default, .default, .cancel])
    }
}
