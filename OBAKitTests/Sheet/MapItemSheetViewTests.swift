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
    private func makeFactory(application: Application) -> AppSheetViewFactory {
        AppSheetViewFactory(
            application: application,
            mapViewModel: MapViewModel(application: application),
            layersModel: MapPanelLayersModel(application: application),
            onPresentTrip: { _ in },
            onPresentVehicleTrip: { _ in },
            presentingController: { nil },
            coordinator: SheetCoordinator(root: .home),
            searchDisplayModel: MapSearchDisplayModel(),
            stopsObserver: MapStopsObserver(application: application)
        )
    }

    @MainActor
    private func makeViewModel(actions: MapItemActions, planTripHandler: (() -> Void)? = {}) -> MapItemViewModel {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3))
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Pike Place Market"
        return MapItemViewModel(
            mapItem: mapItem,
            application: application,
            actions: actions,
            removePinHandler: nil,
            planTripHandler: planTripHandler
        )
    }

    private static let noopActions = MapItemActions(openWebsite: { _ in }, showNearbyStops: { _ in }, dismiss: { })

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

    /// The sheet has no trip-planner destination to hand off to, so it passes a `nil`
    /// handler — which must hide the button rather than render one that no-ops.
    @Test @MainActor
    func `A nil plan trip handler hides the plan trip button`() {
        let viewModel = makeViewModel(actions: Self.noopActions, planTripHandler: nil)

        #expect(viewModel.showPlanTripButton == false)

        // Tapping it anyway (the button is gone, but the method is reachable) must
        // not trap on a force-unwrapped handler.
        viewModel.planTrip()
    }

    @Test @MainActor
    func `A supplied plan trip handler is invoked`() {
        var planned = false
        let viewModel = makeViewModel(actions: Self.noopActions, planTripHandler: { planned = true })

        viewModel.planTrip()

        #expect(planned == true)
    }

    @Test @MainActor
    func `Factory builds a map item sheet for the route`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let factory = makeFactory(application: application)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))

        let view = factory.mapItemView(mapItem: item)

        #expect(view.application === application)
        #expect(view.mapItem === item)
    }

    @Test @MainActor
    func `Factory builds a nearby stops view for the route`() {
        let application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))
        let factory = makeFactory(application: application)
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let view = factory.nearbyStopsView(coordinate: coordinate)

        #expect(view.application === application)
        #expect(view.coordinate?.latitude == coordinate.latitude)
    }
}
