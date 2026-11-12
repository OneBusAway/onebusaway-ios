//
//  SearchInteractorTests.swift
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

/// What the search list offers for a given query.
@Suite(.serialized)
final class SearchInteractorTests: OBATestCase {

    private var queue: OperationQueue!

    /// `SearchInteractor` holds its delegate weakly, so the suite keeps it alive.
    private var delegate: StubDelegate!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @MainActor
    private final class StubDelegate: NSObject, SearchDelegate {
        func performSearch(request: SearchRequest) { }
        func showMapItem(_ mapItem: MKMapItem) { }
        func searchInteractor(_ searchInteractor: SearchInteractor, showStop stop: Stop) { }
        func searchInteractorClearRecentSearches(_ searchInteractor: SearchInteractor) { }
        var isVehicleSearchAvailable: Bool { false }
    }

    @MainActor
    private func makeInteractor() -> (SearchInteractor, Application) {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stub = StubDelegate()
        delegate = stub
        return (SearchInteractor(application: application, delegate: stub), application)
    }

    // MARK: - Empty query

    /// The empty query offers recent *searches* and nothing else — matching the UIKit
    /// panel, which has never surfaced recent stops here.
    @Test @MainActor
    func `An empty query shows recent searches only`() throws {
        let (interactor, application) = makeInteractor()

        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"
        application.userDataStore.addRecentMapItem(item)

        // Present, and deliberately not offered on an empty query.
        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        interactor.searchModeObjects(text: "")

        #expect(interactor.sections.map(\.id) == [.recentMapItems])
    }

    /// No recent searches means no sections at all, so the view falls through to its
    /// empty state. Recent stops are *not* used as a stand-in.
    @Test @MainActor
    func `An empty query with no recent searches shows nothing`() throws {
        let (interactor, application) = makeInteractor()
        application.userDataStore.deleteAllRecentMapItems()

        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        interactor.searchModeObjects(text: "")

        #expect(interactor.sections.isEmpty)
    }

    // MARK: - Recent stops

    /// Recent stops are matched against a typed query, which is the only place they
    /// appear.
    @Test @MainActor
    func `A query matches recent stops by name`() throws {
        let (interactor, application) = makeInteractor()
        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        interactor.searchModeObjects(text: stop.name)

        let section = try #require(interactor.sections.first { $0.id == .recentStops })
        #expect(section.content.map(\.title) == [stop.name])
    }

    /// Recent-stop rows render in a `ForEach`, and stop names repeat across the two
    /// directions of a corner — the row id has to come from the stop, not the title,
    /// or a query matching both drops one of them.
    @Test @MainActor
    func `Recent stops sharing a name get distinct row ids`() throws {
        let (interactor, application) = makeInteractor()

        let stops = try Fixtures.loadSomeStops()
        let sharedName = try #require(
            Dictionary(grouping: stops, by: \.name).first { $0.value.count > 1 }?.value,
            "Fixture no longer contains two stops sharing a name; pick another fixture."
        )
        for stop in sharedName {
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

        interactor.searchModeObjects(text: try #require(sharedName.first).name)

        let section = try #require(interactor.sections.first { $0.id == .recentStops })
        #expect(section.content.count == sharedName.count)
        #expect(Set(section.content.map(\.id)).count == section.content.count)
    }

    // MARK: - Scoping tags

    @Test @MainActor
    func `Stops scope filters quick search to stop number and shows recent stops and bookmarks`() throws {
        let (interactor, application) = makeInteractor()
        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        let bookmark = Bookmark(name: stop.name, regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        application.userDataStore.add(bookmark, to: nil)

        interactor.searchModeObjects(text: stop.name, scope: .stops)

        let sectionIDs = interactor.sections.map(\.id)
        #expect(sectionIDs.contains(.quickSearch))
        #expect(sectionIDs.contains(.recentStops))
        #expect(sectionIDs.contains(.bookmarks))
        #expect(!sectionIDs.contains(.placemarks))

        let quickSearch = try #require(interactor.sections.first { $0.id == .quickSearch })
        #expect(quickSearch.content.map(\.kind.stableIdentifier) == ["quickSearch-\(SearchType.stopNumber.rawValue)"])
    }

    @Test @MainActor
    func `Stops scope with empty query surfaces recent stops and bookmarks without recent map items`() throws {
        let (interactor, application) = makeInteractor()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"
        application.userDataStore.addRecentMapItem(item)

        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        interactor.searchModeObjects(text: "", scope: .stops)

        #expect(interactor.sections.map(\.id) == [.recentStops])
    }

    @Test @MainActor
    func `Routes scope filters quick search to route and excludes stops, bookmarks, and placemarks`() throws {
        let (interactor, application) = makeInteractor()
        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        application.mapRegionManager.lastVisibleMapRect = MKMapRect.world

        interactor.searchModeObjects(text: stop.name, scope: .routes)

        #expect(interactor.sections.map(\.id) == [.quickSearch])
        let quickSearch = try #require(interactor.sections.first { $0.id == .quickSearch })
        #expect(quickSearch.content.map(\.kind.stableIdentifier) == ["quickSearch-\(SearchType.route.rawValue)"])
    }

    @Test @MainActor
    func `Places scope filters quick search to address and excludes recent stops and bookmarks`() throws {
        let (interactor, application) = makeInteractor()
        let stop = try #require(try Fixtures.loadSomeStops().first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)

        interactor.searchModeObjects(text: stop.name, scope: .places)

        let sectionIDs = interactor.sections.map(\.id)
        #expect(!sectionIDs.contains(.recentStops))
        #expect(!sectionIDs.contains(.bookmarks))
        let quickSearch = try #require(interactor.sections.first { $0.id == .quickSearch })
        #expect(quickSearch.content.map(\.kind.stableIdentifier) == ["quickSearch-\(SearchType.address.rawValue)"])
    }

    @Test @MainActor
    func `Places scope with empty query shows recent map items`() {
        let (interactor, application) = makeInteractor()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"
        application.userDataStore.addRecentMapItem(item)

        interactor.searchModeObjects(text: "", scope: .places)

        #expect(interactor.sections.map(\.id) == [.recentMapItems])
    }

    @Test @MainActor
    func `Shortening a place query cancels its pending search`() async throws {
        let (interactor, application) = makeInteractor()
        application.mapRegionManager.lastVisibleMapRect = MKMapRect.world

        interactor.searchModeObjects(text: "ab", scope: .places)
        interactor.searchModeObjects(text: "a", scope: .places)

        try await Task.sleep(for: .milliseconds(500))

        #expect(!interactor.sections.contains { $0.id == .placemarks })
    }

    @Test @MainActor
    func `Routes scope with empty query shows no sections`() {
        let (interactor, application) = makeInteractor()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"
        application.userDataStore.addRecentMapItem(item)

        interactor.searchModeObjects(text: "", scope: .routes)

        #expect(interactor.sections.isEmpty)
    }
}
