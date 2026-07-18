//
//  ServiceAlertViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

/// Tests for `ServiceAlertViewModel`. Verifies HTML build, idempotent
/// `viewDidAppear()`, and mark-as-read side effect.
final class ServiceAlertViewModelTests: OBATestCase {
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
        return try XCTUnwrap(response.references?.serviceAlerts.first)
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

    @MainActor
    func test_renderedHTML_isNil_beforeViewDidAppear() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        expect(viewModel.renderedHTML).to(beNil())
    }

    @MainActor
    func test_viewDidAppear_buildsHTML_andContainsCoreSections() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()

        let html = await waitForRender(viewModel: viewModel)
        let rendered = try XCTUnwrap(html)
        expect(rendered).to(contain("<html>"))
        expect(rendered).to(contain("</html>"))
        expect(rendered).to(contain("<h1>"))
        // The fixture's situation has at least one active window + an affected route.
        expect(rendered).to(contain("In Effect"))
    }

    @MainActor
    func test_viewDidAppear_marksAlertAsRead() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alert = try loadServiceAlert()

        expect(app.userDataStore.isUnread(serviceAlert: alert)).to(beTrue())

        let viewModel = ServiceAlertViewModel(serviceAlert: alert, application: app)
        viewModel.viewDidAppear()

        expect(app.userDataStore.isUnread(serviceAlert: alert)).to(beFalse())
    }

    @MainActor
    func test_viewDidAppear_isIdempotent() async throws {
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
        expect(viewModel.renderedHTML) == firstHTML
    }
}
