//
//  MapViewControllerVisibleMapTests.swift
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

/// Route mode swaps a second map view in front of the main one, and the toolbar
/// keeps driving whichever is on screen. These tests pin down which map
/// `visibleMapView` names on each side of that swap.
@MainActor
@Suite(.serialized)
final class MapViewControllerVisibleMapTests: OBATestCase {

    private var application: Application!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        application = buildApplication(queue: queue, dataLoader: dataLoader)
    }

    /// Guards the trap this fix was written around: `tripPlannerMapView` is lazy
    /// and starts out `isHidden == false`, so a check against `isHidden` would
    /// name it here — and recenter would drive the invisible map behind the one
    /// the rider is looking at. Deliberately never touches `tripPlannerMapView`,
    /// so a regression that builds the map to answer the question fails too.
    @Test func `Names the main map before any trip is planned`() {
        let controller = MapViewController(application: application)

        #expect(controller.isShowingTripPlannerMap == false)
        #expect(controller.visibleMapView === application.mapRegionManager.mapView)
    }

    @Test func `Names the trip planner map in route mode`() {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()

        controller.showTripPlannerMapView()

        #expect(controller.isShowingTripPlannerMap)
        #expect(controller.visibleMapView === controller.tripPlannerMapView)
    }

    @Test func `Names the main map again once route mode ends`() {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()

        controller.showTripPlannerMapView()
        controller.hideTripPlannerMapView()

        #expect(controller.isShowingTripPlannerMap == false)
        #expect(controller.visibleMapView === application.mapRegionManager.mapView)
    }
}
