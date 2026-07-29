//
//  ServiceAlertViewModelTests.swift
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

// swiftlint:disable force_try

/// Tests for `ServiceAlertViewModel`. Verifies HTML build, idempotent
/// `viewDidAppear()`, and mark-as-read side effect.
@Suite(.serialized)
final class ServiceAlertViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

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

    private func loadServiceAlert() throws -> ServiceAlert {
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        return try #require(response.references?.serviceAlerts.first)
    }

    @MainActor
    private func waitForRender(viewModel: ServiceAlertViewModel) async -> String? {
        for _ in 0..<50 {
            if let html = viewModel.renderedHTML { return html }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return viewModel.renderedHTML
    }

    // MARK: - Tests

    @Test @MainActor
    func `Rendered HTML is nil before view did appear`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        #expect(viewModel.renderedHTML == nil)
    }

    @Test @MainActor
    func `View did appear builds HTML and contains core sections`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()

        let html = await waitForRender(viewModel: viewModel)
        let rendered = try #require(html)
        #expect(rendered.contains("<html>"))
        #expect(rendered.contains("</html>"))
        #expect(rendered.contains("<h1>"))
        // The fixture's situation has at least one active window + an affected route.
        #expect(rendered.contains("In Effect"))
    }

    @Test @MainActor
    func `View did appear marks alert as read`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        #expect(app.userDataStore.isUnread(serviceAlert: alert))

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()

        #expect(!app.userDataStore.isUnread(serviceAlert: alert))
    }

    @Test @MainActor
    func `View did appear is idempotent`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()
        _ = await waitForRender(viewModel: viewModel)
        let firstHTML = viewModel.renderedHTML

        viewModel.viewDidAppear()
        // Allow a tick to confirm no re-render mutates the value to something else.
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(viewModel.renderedHTML == firstHTML)
    }
}
