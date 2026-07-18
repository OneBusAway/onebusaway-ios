//
//  RecentStopsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import CoreLocation
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class RecentStopsViewModelTests: OBATestCase {
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

    func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)

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
            dataLoader: dataLoader
        )

        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        return Application(config: config)
    }

    // MARK: - Initial State

    @MainActor
    func test_init_alarmsIsEmpty() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = RecentStopsViewModel(application: app)

        expect(viewModel.alarms).to(beEmpty())
    }

    @MainActor
    func test_init_recentStopsIsEmpty() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = RecentStopsViewModel(application: app)

        expect(viewModel.recentStops).to(beEmpty())
    }

    // MARK: - loadData

    @MainActor
    func test_loadData_populatesRecentStopsForCurrentRegion() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        expect(viewModel.recentStops).to(contain(stop))
    }

    @MainActor
    func test_loadData_excludesStopsFromOtherRegions() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.tampaRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.tampaRegion)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        expect(viewModel.recentStops).to(beEmpty())
    }

    @MainActor
    func test_loadData_populatesAlarms() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let alarm = try! Fixtures.loadAlarm()
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        expect(viewModel.alarms.map(\.url)).to(contain(alarm.url))
    }

    // MARK: - deleteAllRecentStops

    @MainActor
    func test_deleteAllRecentStops_emptiesRecentStops() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stops = try! Fixtures.loadSomeStops()
        stops.prefix(3).forEach {
            $0.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            app.userDataStore.addRecentStop($0, region: Fixtures.pugetSoundRegion)
        }
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()
        expect(viewModel.recentStops).toNot(beEmpty())

        viewModel.deleteAllRecentStops()

        expect(viewModel.recentStops).to(beEmpty())
    }

    // MARK: - delete(recentStop:)

    @MainActor
    func test_delete_recentStop_removesItAndKeepsOthers() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stops = try! Fixtures.loadSomeStops()
        let stopA = stops[0]
        let stopB = stops[1]
        stopA.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        stopB.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stopA, region: Fixtures.pugetSoundRegion)
        app.userDataStore.addRecentStop(stopB, region: Fixtures.pugetSoundRegion)
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        viewModel.delete(recentStop: stopA)

        expect(viewModel.recentStops).toNot(contain(stopA))
        expect(viewModel.recentStops).to(contain(stopB))
    }

    // MARK: - delete(alarm:)

    @MainActor
    func test_delete_alarm_removesItLocally() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alarm = try! Fixtures.loadAlarm()
        // Stub the obaco DELETE *after* createApplication so we don't shadow the
        // regions-v3.json stub it registers (mockResponses is iterated in registration
        // order, and a catch-all here would blank the regions load and silently
        // disable obacoService construction).
        dataLoader.mock(data: Data()) { req in
            req.url?.path.contains("/alarms/") ?? false
        }
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()
        expect(viewModel.alarms.map(\.url)).to(contain(alarm.url))

        // Await the returned Task so the remote DELETE completes inside the test
        // boundary — otherwise it races past tearDown.
        await viewModel.delete(alarm: alarm).value

        expect(viewModel.alarms.map(\.url)).toNot(contain(alarm.url))
    }

    @MainActor
    func test_delete_alarm_remoteSuccess_keepsLocalRemoval() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alarm = try! Fixtures.loadAlarm()

        // Track whether the remote DELETE actually hit the stub. The catch-all matcher
        // pattern from the local-only test would silently disable obaco; we want this
        // test to *fail* if the remote call is short-circuited.
        var didHitRemote = false
        dataLoader.mock(data: Data(), matcher: { req in
            if req.url?.path.contains("/alarms/") == true {
                didHitRemote = true
                return true
            }
            return false
        })

        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        await viewModel.delete(alarm: alarm).value

        expect(viewModel.alarms.map(\.url)).toNot(contain(alarm.url))
        expect(didHitRemote).to(beTrue())
    }

    @MainActor
    func test_delete_alarm_remoteFailure_keepsLocalRemoval() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alarm = try! Fixtures.loadAlarm()

        // Stub the obaco DELETE to fail. Local removal should still hold and the Task
        // should swallow the error via Logger.error (so awaiting it doesn't throw).
        let remoteError = NSError(domain: "RecentStopsViewModelTests", code: 503, userInfo: nil)
        dataLoader.mock(response: MockDataResponse(
            data: nil, urlResponse: nil, error: remoteError,
            matcher: { $0.url?.path.contains("/alarms/") ?? false }
        ))

        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        await viewModel.delete(alarm: alarm).value

        // Remote failure does not undo the local removal — that's the contract.
        expect(viewModel.alarms.map(\.url)).toNot(contain(alarm.url))
    }

    // MARK: - loadData / nil currentRegion

    @MainActor
    func test_loadData_nilCurrentRegion_recentStopsIsEmpty() {
        // Use "Null Island" (0, 0) which is in the Gulf of Guinea — not covered by any
        // transit region — so application.currentRegion is nil when loadData() runs.
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let nullIslandLocation = CLLocation(latitude: 0, longitude: 0)
        let locManager = MockAuthorizedLocationManager(
            updateLocation: nullIslandLocation,
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
            dataLoader: dataLoader
        )
        let app = Application(config: config)

        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = nil
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        let viewModel = RecentStopsViewModel(application: app)

        // Pin the precondition the test relies on: if a future stub region ever covers
        // (0,0) (e.g. a worldwide bounding box), `currentRegion` would become non-nil
        // and the assertion below would pass for the wrong reason.
        expect(app.currentRegion).to(beNil())

        viewModel.loadData()

        // When currentRegion is nil, loadData() exits early and returns an empty list —
        // no accidental nil == nil matches.
        expect(viewModel.recentStops).to(beEmpty())
    }
}
