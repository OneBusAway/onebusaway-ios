//
//  RecentStopsViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class RecentStopsViewModelTests: OBATestCase {
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

    @Test @MainActor
    func `Init alarms is empty`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = RecentStopsViewModel(application: app)

        #expect(viewModel.alarms.isEmpty)
    }

    @Test @MainActor
    func `Init recent stops is empty`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let viewModel = RecentStopsViewModel(application: app)

        #expect(viewModel.recentStops.isEmpty)
    }

    // MARK: - loadData

    @Test @MainActor
    func `Load data populates recent stops for current region`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        #expect(viewModel.recentStops.contains(stop))
    }

    @Test @MainActor
    func `Load data excludes stops from other regions`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.tampaRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.tampaRegion)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        #expect(viewModel.recentStops.isEmpty)
    }

    @Test @MainActor
    func `Load data populates alarms`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let alarm = try! Fixtures.loadAlarm()
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)

        viewModel.loadData()

        #expect(viewModel.alarms.map(\.url).contains(alarm.url))
    }

    // MARK: - deleteAllRecentStops

    @Test @MainActor
    func `Delete all recent stops empties recent stops`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stops = try! Fixtures.loadSomeStops()
        stops.prefix(3).forEach {
            $0.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            app.userDataStore.addRecentStop($0, region: Fixtures.pugetSoundRegion)
        }
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()
        #expect(!viewModel.recentStops.isEmpty)

        viewModel.deleteAllRecentStops()

        #expect(viewModel.recentStops.isEmpty)
    }

    // MARK: - delete(recentStop:)

    @Test @MainActor
    func `Delete recent stop removes it and keeps others`() {
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

        #expect(!viewModel.recentStops.contains(stopA))
        #expect(viewModel.recentStops.contains(stopB))
    }

    // MARK: - delete(alarm:)

    @Test @MainActor
    func `Delete alarm removes it locally`() async {
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
        #expect(viewModel.alarms.map(\.url).contains(alarm.url))

        // Await the returned Task so the remote DELETE completes inside the test
        // boundary — otherwise it races past the end of the test.
        await viewModel.delete(alarm: alarm).value

        #expect(!viewModel.alarms.map(\.url).contains(alarm.url))
    }

    @Test @MainActor
    func `Delete alarm remote success keeps local removal`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let alarm = try! Fixtures.loadAlarm()

        // Track whether the remote DELETE actually hit the stub. The catch-all matcher
        // pattern from the local-only test would silently disable obaco; we want this
        // test to *fail* if the remote call is short-circuited.
        // Boxed: the matcher is @Sendable and cannot write to a main-actor local.
        let didHitRemote = SendableBox(false)
        dataLoader.mock(data: Data(), matcher: { req in
            if req.url?.path.contains("/alarms/") == true {
                didHitRemote.value = true
                return true
            }
            return false
        })

        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)
        app.userDataStore.add(alarm: alarm)
        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        await viewModel.delete(alarm: alarm).value

        #expect(!viewModel.alarms.map(\.url).contains(alarm.url))
        #expect(didHitRemote.value)
    }

    @Test @MainActor
    func `Delete alarm remote failure keeps local removal`() async {
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
        #expect(!viewModel.alarms.map(\.url).contains(alarm.url))
    }

    // MARK: - loadData / nil currentRegion

    @Test @MainActor
    func `Load data nil current region recent stops is empty`() {
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
        #expect(app.currentRegion == nil)

        viewModel.loadData()

        // When currentRegion is nil, loadData() exits early and returns an empty list —
        // no accidental nil == nil matches.
        #expect(viewModel.recentStops.isEmpty)
    }

    // MARK: - Quick Bookmarking

    @Test @MainActor
    func `isBookmarked is false initially and true after toggleBookmark`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        #expect(!viewModel.isBookmarked(stop))
        #expect(app.userDataStore.findBookmark(stopID: stop.id) == nil)

        viewModel.toggleBookmark(for: stop)

        #expect(viewModel.isBookmarked(stop))
        let saved = app.userDataStore.findBookmark(stopID: stop.id)
        #expect(saved != nil)
        #expect(saved?.name == stop.name)
        #expect(saved?.isTripBookmark == false)
    }

    @Test @MainActor
    func `toggleBookmark removes existing whole-stop bookmark on second toggle`() {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try! Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()
        viewModel.toggleBookmark(for: stop)
        #expect(viewModel.isBookmarked(stop))

        viewModel.toggleBookmark(for: stop)

        #expect(!viewModel.isBookmarked(stop))
        #expect(app.userDataStore.findBookmark(stopID: stop.id) == nil)
    }

    @Test @MainActor
    func `toggleBookmark preserves trip bookmarks for the same stop`() throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
        let stop = try #require(arrivalDeparture.stop)
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier

        let tripBookmark = Bookmark(
            name: "My Commute",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            arrivalDeparture: arrivalDeparture
        )
        app.userDataStore.add(tripBookmark, to: nil)
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()

        // Trip bookmark alone does not count as a whole-stop bookmark.
        #expect(!viewModel.isBookmarked(stop))

        viewModel.toggleBookmark(for: stop)
        #expect(viewModel.isBookmarked(stop))
        #expect(app.userDataStore.bookmarks.contains(where: { $0.id == tripBookmark.id }))

        viewModel.toggleBookmark(for: stop)
        #expect(!viewModel.isBookmarked(stop))
        #expect(app.userDataStore.bookmarks.contains(where: { $0.id == tripBookmark.id }))
    }

    @Test @MainActor
    func `External bookmark changes sync bookmarkedStopIDs via notification`() async throws {
        let app = createApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try Fixtures.loadSomeStops().first!
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        app.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = RecentStopsViewModel(application: app)
        viewModel.loadData()
        #expect(!viewModel.isBookmarked(stop))

        let bookmark = Bookmark(
            name: stop.name,
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: stop
        )
        app.userDataStore.add(bookmark, to: nil)

        for _ in 0..<20 where !viewModel.isBookmarked(stop) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.isBookmarked(stop))

        app.userDataStore.delete(bookmark: bookmark)

        for _ in 0..<20 where viewModel.isBookmarked(stop) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!viewModel.isBookmarked(stop))
    }

    @Test @MainActor
    func `toggleBookmark is a no-op when region is unavailable`() throws {
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
        try #require(app.currentRegion == nil)

        let stop = try Fixtures.loadSomeStops().first!
        stop.regionIdentifier = nil

        let viewModel = RecentStopsViewModel(application: app)
        viewModel.toggleBookmark(for: stop)

        #expect(!viewModel.isBookmarked(stop))
        #expect(app.userDataStore.bookmarks.isEmpty)
    }
}
