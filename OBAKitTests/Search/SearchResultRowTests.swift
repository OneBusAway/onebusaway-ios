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
}
