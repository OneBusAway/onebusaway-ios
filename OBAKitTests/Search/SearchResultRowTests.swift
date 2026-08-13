//
//  SearchResultRowTests.swift
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

/// Row mapping for the disambiguation sheet: one row per result type, reusing the
/// same row model as the search list so the two screens look alike.
@Suite(.serialized)
final class SearchResultRowTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test @MainActor
    func `A stop result becomes a titled row`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let row = try #require(SearchResultRow.row(for: stop, application: application, onSelect: { }))

        #expect(row.title == stop.name)
        #expect(row.accessory == .disclosureIndicator)
    }

    @Test @MainActor
    func `A route result shows its short name and agency`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let route = try Fixtures.createRoute(id: "1_44")

        let row = try #require(SearchResultRow.row(for: route, application: application, onSelect: { }))

        #expect(row.title == route.shortName)
        #expect(row.subtitle?.isEmpty == false)
    }

    @Test @MainActor
    func `A map item result shows the place name`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        let item = MKMapItem(placemark: placemark)
        item.name = "Pike Place Market"

        let row = try #require(SearchResultRow.row(for: item, application: application, onSelect: { }))

        #expect(row.title == "Pike Place Market")
    }

    @Test @MainActor
    func `An unknown result type produces no row`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        #expect(SearchResultRow.row(for: "just a string", application: application, onSelect: { }) == nil)
    }

    @Test @MainActor
    func `Selecting a row invokes its handler`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stop = try #require(try Fixtures.loadSomeStops().first)
        var selected = false

        let row = try #require(SearchResultRow.row(for: stop, application: application, onSelect: { selected = true }))
        row.action?()

        #expect(selected == true)
    }

    // MARK: - Row identity

    /// The disambiguation list renders through `ForEach`, so ids have to be unique.
    /// Stop names are not: the two directions of a corner share one, and the Seattle
    /// fixture has six such pairs among 26 stops. Deriving ids from titles collided
    /// in exactly the case this list exists to handle.
    @Test @MainActor
    func `Stops sharing a name still get distinct row ids`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let stops = try Fixtures.loadSomeStops()

        let duplicatedName = try #require(
            Dictionary(grouping: stops, by: \.name).first { $0.value.count > 1 }?.value,
            "Fixture no longer contains two stops sharing a name; pick another fixture."
        )

        let rows = duplicatedName.compactMap {
            SearchResultRow.row(for: $0, application: application, onSelect: { })
        }

        #expect(rows.count == duplicatedName.count)
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test @MainActor
    func `Routes sharing a short name still get distinct row ids`() throws {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        // Two agencies can both run a route called "1".
        let first = try Fixtures.createRoute(id: "1_44")
        let second = try Fixtures.createRoute(id: "2_44")

        let rows = [first, second].compactMap {
            SearchResultRow.row(for: $0, application: application, onSelect: { })
        }

        #expect(rows.count == 2)
        #expect(rows[0].title == rows[1].title)
        #expect(rows[0].id != rows[1].id)
    }

    /// The shared factory reproduces what the inline `Stop` branch produced,
    /// for whichever kind the caller asks for.
    @Test @MainActor
    func `Stop factory builds a row with the requested kind`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let row = SearchListRow.stop(
            stop,
            application: application,
            kind: .nearbyStop(id: stop.id),
            onSelect: {}
        )

        #expect(row.title == stop.name)
        #expect(row.accessory == .disclosureIndicator)
        if case .nearbyStop(let id) = row.kind {
            #expect(id == stop.id)
        } else {
            Issue.record("Expected a .nearbyStop kind, got \(row.kind)")
        }
    }

    /// A stop shown in both the nearby and recent sections must not produce two
    /// rows with the same `id`, or `ForEach` collapses them.
    @Test @MainActor
    func `Nearby and recent kinds yield distinct identifiers for one stop`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stop = try #require(try Fixtures.loadSomeStops().first)

        let nearby = SearchListRow.stop(stop, application: application, kind: .nearbyStop(id: stop.id), onSelect: {})
        let recent = SearchListRow.stop(stop, application: application, kind: .recentStop(id: stop.id), onSelect: {})

        #expect(nearby.id != recent.id)
    }
}
