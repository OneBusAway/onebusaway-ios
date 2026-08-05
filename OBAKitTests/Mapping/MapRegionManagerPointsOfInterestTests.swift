//
//  MapRegionManagerPointsOfInterestTests.swift
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

/// Persistence + map application for the Points of Interest visibility toggle (#1246).
@MainActor
@Suite(.serialized)
final class MapRegionManagerPointsOfInterestTests: OBATestCase {

    private var manager: MapRegionManager!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        manager = MapRegionManager(application: buildApplication(queue: queue, dataLoader: dataLoader))
    }

    @Test func `Defaults to showing points of interest`() {
        #expect(manager.mapViewShowsPointsOfInterest == true)
        #expect(manager.mapView.pointOfInterestFilter == .includingAll)
        #expect(manager.mapView.selectableMapFeatures.contains(.pointsOfInterest))
    }

    @Test func `Hiding POIs updates the map filter and selectable features`() {
        manager.mapViewShowsPointsOfInterest = false

        #expect(manager.mapViewShowsPointsOfInterest == false)
        #expect(manager.mapView.pointOfInterestFilter == .excludingAll)
        #expect(!manager.mapView.selectableMapFeatures.contains(.pointsOfInterest))
        #expect(manager.mapView.selectableMapFeatures.contains(.physicalFeatures))
    }

    @Test func `Showing POIs again restores filter and selection`() {
        manager.mapViewShowsPointsOfInterest = false
        manager.mapViewShowsPointsOfInterest = true

        #expect(manager.mapView.pointOfInterestFilter == .includingAll)
        #expect(manager.mapView.selectableMapFeatures.contains(.pointsOfInterest))
    }

    @Test func `Persists through UserDefaults`() {
        manager.mapViewShowsPointsOfInterest = false
        #expect(userDefaults.bool(forKey: MapRegionManager.mapViewShowsPointsOfInterestKey) == false)

        manager.mapViewShowsPointsOfInterest = true
        #expect(userDefaults.bool(forKey: MapRegionManager.mapViewShowsPointsOfInterestKey) == true)
    }

    @Test func `Posts visibility change notification`() async {
        await confirmation("POI visibility notification") { confirm in
            let observer = NotificationCenter.default.addObserver(
                forName: .mapPointsOfInterestVisibilityDidChange, object: nil, queue: nil
            ) { _ in
                confirm()
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            manager.mapViewShowsPointsOfInterest = false
        }
    }

    @Test func `Identical writes do not re-post`() async {
        manager.mapViewShowsPointsOfInterest = false

        await confirmation("redundant write posts nothing", expectedCount: 0) { confirm in
            let observer = NotificationCenter.default.addObserver(
                forName: .mapPointsOfInterestVisibilityDidChange, object: nil, queue: nil
            ) { _ in
                confirm()
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            manager.mapViewShowsPointsOfInterest = false
        }
    }

    @Test func `Hidden POIs count toward map sheet reset`() {
        #expect(!manager.mapLayersDifferFromDefaults)
        manager.mapViewShowsPointsOfInterest = false
        #expect(manager.mapLayersDifferFromDefaults)

        manager.resetMapLayersToDefaults()
        #expect(manager.mapViewShowsPointsOfInterest == true)
        #expect(!manager.mapLayersDifferFromDefaults)
    }
}
