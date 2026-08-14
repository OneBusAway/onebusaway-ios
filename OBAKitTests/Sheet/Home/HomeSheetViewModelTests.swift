//
//  HomeSheetViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class HomeSheetViewModelTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @MainActor
    private func makeViewModel(application: Application) -> HomeSheetViewModel {
        HomeSheetViewModel(
            application: application,
            stopsObserver: MapStopsObserver(application: application)
        )
    }

    /// With no data at all, every section is omitted — the view renders the
    /// all-empty state rather than three empty headers.
    @Test @MainActor
    func `Visible sections is empty when every section is empty`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let viewModel = makeViewModel(application: application)

        #expect(viewModel.visibleSections.isEmpty)
    }

    /// An empty earlier section does not promote a later one — order is fixed.
    @Test @MainActor
    func `Visible sections keeps a fixed order when an earlier section is empty`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // Seed recents only — nearby stays empty (no map settle) and bookmarks
        // stay empty (none stored).
        let stop = try #require(stops.first)
        // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
        // fixture stops bypass that path, so we assign it here to match production state.
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let viewModel = makeViewModel(application: application)
        viewModel.activate()

        #expect(viewModel.visibleSections == [.recent])
    }

    /// Both populated sections appear, nearby-before-recent order intact.
    @Test @MainActor
    func `Visible sections lists nearby before recent`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)
        // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
        // fixture stops bypass that path, so we assign it here to match production state.
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let viewModel = HomeSheetViewModel(application: application, stopsObserver: observer)
        viewModel.activate()

        #expect(viewModel.visibleSections == [.nearby, .recent])
    }

    /// Every section caps at the shared limit.
    @Test @MainActor
    func `Sections cap at the shared section limit`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        for stop in stops.prefix(HomeSheetSection.itemLimit + 3) {
            // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
            // fixture stops bypass that path, so we assign it here to match production state.
            stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

        let viewModel = makeViewModel(application: application)
        viewModel.activate()

        #expect(viewModel.recent.stops.count == HomeSheetSection.itemLimit)
    }

    /// Two activations in quick succession issue one bookmark fetch.
    @Test @MainActor
    func `Activate twice in quick succession fetches bookmarks once`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        let bookmark = Bookmark(
            name: "Bookmark",
            regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
            stop: try #require(stops.first)
        )
        application.userDataStore.add(bookmark, to: nil)

        let viewModel = makeViewModel(application: application)
        let start = Date()

        #expect(viewModel.bookmarks.loadIfNeeded(now: start))
        #expect(viewModel.bookmarks.loadIfNeeded(now: start.addingTimeInterval(2)) == false)
    }
}
