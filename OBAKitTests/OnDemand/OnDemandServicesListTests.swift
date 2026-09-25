//
//  OnDemandServicesListTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@MainActor
@Suite(.serialized)
final class OnDemandServicesListTests: OBATestCase {
    private var dataLoader: MockDataLoader!

    private static let charlevoixURL = "https://www.example.com/api/ondemand/services-for-agency/CC.json"

    override init() async throws {
        try await super.init()
        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    nonisolated private static func isAgencyListRequest(_ request: URLRequest) -> Bool {
        request.url?.path.contains("/api/ondemand/services-for-agency/") ?? false
    }

    private func stubCharlevoix(_ loader: MockDataLoader) {
        loader.mock(URLString: Self.charlevoixURL, with: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json"))
    }

    private func gatedService(_ gate: GatedDataLoader) -> RESTAPIService {
        let config = APIServiceConfiguration(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, regionIdentifier: pugetSoundRegionIdentifier)
        return RESTAPIService(config, dataLoader: gate, onDemandSupport: OnDemandSupport())
    }

    /// Holds only the `number`th request (1-based), passing the rest through.
    private func gatingRequest(number: Int, holdsAfterResponse: Bool = false) -> GatedDataLoader {
        let requestCount = OSAllocatedUnfairLock(initialState: 0)
        return GatedDataLoader(dataLoader, gating: { _ in
            requestCount.withLock { count in
                count += 1
                return count == number
            }
        }, holdsAfterResponse: holdsAfterResponse)
    }

    // MARK: - Model

    @Test func `Loads an agency's services sorted by id`() async {
        stubCharlevoix(dataLoader)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        #expect(model.state == .loading)
        await model.load()
        guard case .loaded(let services) = model.state else {
            Issue.record("expected loaded, got \(model.state)")
            return
        }
        #expect(services.map(\.id) == ["CC_CC1", "CC_CC2_med", "CC_CC3", "CC_CC4"])
    }

    @Test func `404 for an agency is an empty list`() async {
        dataLoader.mock(data: Data(), statusCode: 404) { Self.isAgencyListRequest($0) }
        let model = OnDemandServicesListModel(agencyID: "nope", apiService: restService, regionName: "Test")
        await model.load()
        #expect(model.state == .loaded([]))
        #expect(!restService.onDemandSupport.isKnownUnsupported(baseURL: restService.baseURL), "a 404 on the agency list never marks the server")
    }

    @Test func `Server error is a failure with rider-facing text`() async {
        dataLoader.mock(data: Data(), statusCode: 500) { Self.isAgencyListRequest($0) }
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        await model.load()
        guard case .failed(let text) = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }
        #expect(!text.isEmpty)
    }

    /// `APIService+GetData` throws `requestNotFound` for a blank 200 too, which
    /// a legacy server may send; it reads as no services, never a failure.
    @Test func `Blank 200 is an empty list`() async {
        dataLoader.mock(data: Data(), statusCode: 200) { Self.isAgencyListRequest($0) }
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        await model.load()
        #expect(model.state == .loaded([]))
    }

    @Test func `Missing API service shows no services`() async {
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: nil, regionName: nil)
        await model.load()
        #expect(model.state == .loaded([]))
    }

    @Test func `Known-unsupported server shows no services without a request`() async {
        restService.onDemandSupport.recordAbsent(baseURL: restService.baseURL)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: restService, regionName: "Test")
        await model.load()
        #expect(model.state == .loaded([]))
        #expect(dataLoader.recordedRequestURLs.isEmpty)
    }

    @Test func `Retry after a failure shows the spinner, then the services`() async {
        dataLoader.mock(data: Data(), statusCode: 500) { Self.isAgencyListRequest($0) }
        let gate = gatingRequest(number: 2)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: gatedService(gate), regionName: "Test")
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed, got \(model.state)")
            return
        }

        dataLoader.replaceMappedResponses { stubCharlevoix($0) }
        let retry = Task { await model.load() }
        await gate.waitForRequest()
        #expect(model.state == .loading)

        gate.releaseRequest()
        await retry.value
        guard case .loaded(let services) = model.state else {
            Issue.record("expected loaded, got \(model.state)")
            return
        }
        #expect(services.count == 4)
    }

    @Test func `Reloading a loaded list keeps it on screen`() async {
        stubCharlevoix(dataLoader)
        let gate = gatingRequest(number: 2)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: gatedService(gate), regionName: "Test")
        await model.load()
        let loaded = model.state

        let reload = Task { await model.load() }
        await gate.waitForRequest()
        #expect(model.state == loaded)

        gate.releaseRequest()
        await reload.value
    }

    /// The first load's failure arrives after a second load has already
    /// succeeded; the list keeps the newer result.
    @Test func `A superseded load does not overwrite the newer result`() async {
        dataLoader.mock(data: Data(), statusCode: 500) { Self.isAgencyListRequest($0) }
        let gate = gatingRequest(number: 1, holdsAfterResponse: true)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: gatedService(gate), regionName: "Test")

        let firstLoad = Task { await model.load() }
        await gate.waitForRequest()

        dataLoader.replaceMappedResponses { stubCharlevoix($0) }
        await model.load()
        #expect(model.state != .loading)

        gate.releaseRequest()
        await firstLoad.value
        guard case .loaded(let services) = model.state else {
            Issue.record("expected the newer loaded result, got \(model.state)")
            return
        }
        #expect(services.count == 4)
    }

    @Test func `A cancelled load leaves the state alone`() async {
        stubCharlevoix(dataLoader)
        let gate = GatedDataLoader(dataLoader, holdsAfterResponse: true)
        let model = OnDemandServicesListModel(agencyID: "CC", apiService: gatedService(gate), regionName: "Test")

        let load = Task { await model.load() }
        await gate.waitForRequest()
        load.cancel()
        gate.releaseRequest()
        await load.value
        #expect(model.state == .loading)
    }

    // MARK: - Agencies screen

    private func buildAgenciesController(onDemandSupport: OnDemandSupport) -> (AgenciesViewController, Application) {
        let loader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: loader, onDemandSupport: onDemandSupport)
        return (AgenciesViewController(application: application), application)
    }

    private func actionTitles(_ alert: UIAlertController) -> [String?] {
        alert.actions.map(\.title)
    }

    @Test func `Agency options offer on-demand services unless the server is known-unsupported`() throws {
        let support = OnDemandSupport()
        let (controller, application) = buildAgenciesController(onDemandSupport: support)
        let agency = try #require(try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json").first)

        #expect(controller.showsOnDemandAction)
        #expect(actionTitles(controller.agencyOptionsAlert(agency)).contains(Strings.agenciesOnDemandServices))

        support.recordAbsent(baseURL: try #require(application.apiService).baseURL)
        #expect(!controller.showsOnDemandAction)
        #expect(!actionTitles(controller.agencyOptionsAlert(agency)).contains(Strings.agenciesOnDemandServices))
    }

    @Test func `Agencies screen without an API service offers no on-demand action`() {
        // An unauthorized location manager and no fixed region leave
        // `currentRegion`, and so `apiService`, nil.
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: OperationQueue(), locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: loader)
        let application = Application(config: config)
        #expect(application.apiService == nil)

        let controller = AgenciesViewController(application: application)
        #expect(!controller.showsOnDemandAction)
    }

    @Test func `On-demand list host is titled for the list and pushes the service page`() throws {
        let (_, application) = buildAgenciesController(onDemandSupport: OnDemandSupport())
        let agency = try #require(try Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json").first)
        let host = OnDemandServicesListViewController(application: application, agency: agency.agency)
        #expect(host.title == Strings.onDemandListTitle)

        let navigation = UINavigationController(rootViewController: host)
        let list = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: Fixtures.loadData(file: "ondemand_services_for_agency_charlevoix.json")).list
        let service = try #require(list.first)
        host.rootView.onSelect(service)
        #expect(navigation.topViewController is OnDemandServiceViewController)
    }
}

// swiftlint:enable force_cast
