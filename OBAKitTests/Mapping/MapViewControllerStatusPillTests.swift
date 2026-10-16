//
//  MapViewControllerStatusPillTests.swift
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

/// The pill at the top of the classic map: "Zoom in for stops", the rentals hint,
/// and location warnings (#1547).
@MainActor
@Suite(.serialized)
final class MapViewControllerStatusPillTests: OBATestCase {

    private var application: Application!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        // The map probes for on-demand services when it settles, and loads stops
        // once it settles at street level.
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.hasSuffix("/stops-for-location.json") ?? false
        }
        application = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    /// Seen on device: zoomed in to the street, stops on screen, and the pill still
    /// said "Zoom in for stops". The redraw ran inside the change: `@Published` sends
    /// before it stores, and drawing settles the map, which updates the warning
    /// again from inside the send, where Combine drops it. Only the stops flag
    /// flips here, as it does whenever the rentals hint doesn't flip with it.
    @Test func `The stops pill follows each zoom change, not the one before it`() async {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()

        controller.viewModel.updateZoomWarnings(stops: true, rentals: false)
        await mainQueueTurn()
        #expect(controller.mapStatusView.indicator == .zoomInForStops)

        controller.viewModel.updateZoomWarnings(stops: false, rentals: false)
        await mainQueueTurn()
        #expect(controller.mapStatusView.indicator != .zoomInForStops)

        controller.viewModel.updateZoomWarnings(stops: true, rentals: false)
        await mainQueueTurn()
        #expect(controller.mapStatusView.indicator == .zoomInForStops)
    }

    /// Lets the pill's redraw, queued behind the change, run.
    private func mainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// In route mode the trip planner's map covers the main one, which the zoom
    /// warnings describe. Shown there, the pill would talk about a map the rider
    /// can't see, and tapping it would zoom that hidden map.
    @Test func `The zoom pill stands down in route mode and comes back after`() async {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()
        controller.viewModel.updateZoomWarnings(stops: true, rentals: false)
        await mainQueueTurn()
        #expect(controller.mapStatusView.indicator == .zoomInForStops)

        controller.showTripPlannerMapView()
        #expect(controller.mapStatusView.indicator != .zoomInForStops)

        controller.hideTripPlannerMapView()
        #expect(controller.mapStatusView.indicator == .zoomInForStops)
    }

    /// Leaving route mode brings back the main map at the trip map's region. The
    /// pill has to judge that region, not the one the main map had on the way in:
    /// zoomed in on the trip map, it would otherwise come back saying "Zoom in for
    /// stops" over a street-level map.
    @Test func `Leaving route mode judges the region the main map comes back at`() async {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        controller.viewModel.updateZoomWarnings(stops: true, rentals: false)
        await mainQueueTurn()

        controller.showTripPlannerMapView()
        controller.view.layoutIfNeeded()
        controller.tripPlannerMapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        controller.hideTripPlannerMapView()

        #expect(controller.mapStatusView.indicator != .zoomInForStops)
    }
}
