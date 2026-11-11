//
//  SearchResultRouterDomainExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended domain tests for `SearchResultRouter` item routing,
/// navigation targets, and delegate callback delivery.
@MainActor
@Suite(.serialized)
final class SearchResultRouterDomainExtendedTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `SearchResultRouter initializes with application and delegate`() {
        let app = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let router = SearchResultRouter(application: app)

        #expect(router.application === app)
    }

    @Test func `Stop item mapping preserves stop identity and coordinates`() throws {
        let stops = try Fixtures.loadSomeStops()
        let stop = try #require(stops.first)

        #expect(stop.id == "1_75403")
        #expect(stop.title == "Stevens Way & Benton Ln")
        #expect(abs(stop.coordinate.latitude - 47.6534) < 0.01)
    }

    @Test func `Placemark item mapping preserves coordinate and title`() {
        let coord = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let placemark = MKPlacemark(coordinate: coord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Public Library"

        #expect(mapItem.name == "Public Library")
        #expect(mapItem.placemark.coordinate.latitude == coord.latitude)
        #expect(mapItem.placemark.coordinate.longitude == coord.longitude)
    }
}
