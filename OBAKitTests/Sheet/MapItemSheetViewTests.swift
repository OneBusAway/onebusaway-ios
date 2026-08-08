//
//  MapItemSheetViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The map-item sheet's wiring: injected actions and the share URL the native
/// `ShareLink` uses.
@Suite(.serialized)
final class MapItemSheetViewTests: OBATestCase {

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
    private func makeViewModel(actions: MapItemActions) -> MapItemViewModel {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Pike Place Market"
        return MapItemViewModel(
            mapItem: mapItem,
            application: application,
            actions: actions,
            removePinHandler: nil,
            planTripHandler: {}
        )
    }

    @Test @MainActor
    func `Dismissing routes through the injected action`() {
        var dismissed = false
        let viewModel = makeViewModel(actions: MapItemActions(
            openWebsite: { _ in },
            showNearbyStops: { _ in },
            dismiss: { dismissed = true }
        ))

        viewModel.dismissView()

        #expect(dismissed == true)
    }

    @Test @MainActor
    func `Nearby stops routes through the injected action with the item coordinate`() {
        var received: CLLocationCoordinate2D?
        let viewModel = makeViewModel(actions: MapItemActions(
            openWebsite: { _ in },
            showNearbyStops: { received = $0 },
            dismiss: { }
        ))

        viewModel.showNearbyStops()

        let coordinate = try? #require(received)
        #expect(coordinate?.latitude == 47.6)
    }

    /// The sheet header uses a native `ShareLink`, so the view model exposes the URL
    /// rather than presenting a `UIActivityViewController` itself.
    @Test @MainActor
    func `Share URL falls back to a query and coordinates link`() throws {
        let viewModel = makeViewModel(actions: MapItemActions(openWebsite: { _ in }, showNearbyStops: { _ in }, dismiss: { }))

        let url = try #require(viewModel.shareURL)

        #expect(url.absoluteString.contains("maps.apple.com"))
        #expect(url.absoluteString.contains("47.6"))
    }

    @Test @MainActor
    func `Factory builds a map item sheet for the route`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in }, presentingController: { nil })
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))

        let view = factory.mapItemView(mapItem: item)

        #expect(view.application === application)
        #expect(view.mapItem === item)
    }

    @Test @MainActor
    func `Factory builds a nearby stops host for the route`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in }, presentingController: { nil })
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let host = factory.nearbyStopsView(coordinate: coordinate)

        #expect(host.application === application)
        #expect(host.coordinate.latitude == coordinate.latitude)
    }
}
