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

    // MARK: - Basemap switching cleanup & lifecycle

    private func attachTileOverlayAndCacheRenderer() -> (overlay: MKTileOverlay, renderer: MKOverlayRenderer) {
        let tileOverlay = MKTileOverlay(urlTemplate: "https://example.com/tiles/{z}/{x}/{y}.png")
        manager.mapView.addOverlay(tileOverlay)
        let renderer = manager.mapView(manager.mapView, rendererFor: tileOverlay)
        return (tileOverlay, renderer)
    }

    @Test func `Cycling basemaps removes obsolete tile overlays and leaves zero orphaned overlays`() {
        let cycle: [(MapBaseType, MKMapType)] = [
            (.satellite, .satellite),
            (.hybrid, .hybrid),
            (.standard, .mutedStandard)
        ]

        for (baseType, expectedMKMapType) in cycle {
            _ = attachTileOverlayAndCacheRenderer()
            #expect(manager.mapView.overlays.contains { $0 is MKTileOverlay })

            manager.setBaseMapType(baseType)

            #expect(manager.mapView.mapType == expectedMKMapType)
            #expect(!manager.mapView.overlays.contains { $0 is MKTileOverlay })
            #expect(manager.mapView.overlays.isEmpty)
        }
    }

    @Test func `Cycling basemaps preserves non-tile polyline overlays while removing tile overlays`() {
        var coords = [
            CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
            CLLocationCoordinate2D(latitude: 47.6205, longitude: -122.3493)
        ]
        let routePolyline = MKPolyline(coordinates: &coords, count: coords.count)
        manager.mapView.addOverlay(routePolyline)
        _ = attachTileOverlayAndCacheRenderer()

        manager.setBaseMapType(.satellite)
        #expect(!manager.mapView.overlays.contains { $0 is MKTileOverlay })
        #expect(manager.mapView.overlays.contains { $0 === routePolyline })

        manager.setBaseMapType(.hybrid)
        #expect(!manager.mapView.overlays.contains { $0 is MKTileOverlay })
        #expect(manager.mapView.overlays.contains { $0 === routePolyline })

        manager.setBaseMapType(.standard)
        #expect(!manager.mapView.overlays.contains { $0 is MKTileOverlay })
        #expect(manager.mapView.overlays.contains { $0 === routePolyline })
    }

    @Test func `Cycling basemaps invalidates renderer caches and releases tile overlays and renderers`() {
        weak var weakOverlay: MKTileOverlay?
        weak var weakRenderer: MKOverlayRenderer?

        autoreleasepool {
            let pair = attachTileOverlayAndCacheRenderer()
            weakOverlay = pair.overlay
            weakRenderer = pair.renderer
            #expect(manager.cachedOverlayRendererCount == 1)
        }

        let initialInvalidations = manager.rendererCacheInvalidationCount

        autoreleasepool {
            manager.setBaseMapType(.satellite)
        }

        #expect(manager.cachedOverlayRendererCount == 0)
        #expect(manager.rendererCacheInvalidationCount == initialInvalidations + 1)
        #expect(weakOverlay == nil)
        #expect(weakRenderer == nil)

        // Switching to hybrid and back to standard continues invalidating cleanly.
        autoreleasepool {
            _ = attachTileOverlayAndCacheRenderer()
            #expect(manager.cachedOverlayRendererCount == 1)
            manager.setBaseMapType(.hybrid)
        }
        #expect(manager.cachedOverlayRendererCount == 0)
        #expect(manager.rendererCacheInvalidationCount == initialInvalidations + 2)

        autoreleasepool {
            _ = attachTileOverlayAndCacheRenderer()
            #expect(manager.cachedOverlayRendererCount == 1)
            manager.setBaseMapType(.standard)
        }
        #expect(manager.cachedOverlayRendererCount == 0)
        #expect(manager.rendererCacheInvalidationCount == initialInvalidations + 3)

        // Redundant write of the active basemap does not churn caches.
        manager.setBaseMapType(.standard)
        #expect(manager.rendererCacheInvalidationCount == initialInvalidations + 3)
    }

    @Test func `Switching basemaps resets and reconciles camera margins`() {
        manager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 16, bottom: 120, trailing: 16)
        manager.setBaseMapType(.satellite)

        #expect(manager.mapView.directionalLayoutMargins == .zero)
        #expect(manager.mapView.layoutMargins == .zero)

        let customBaseline = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 64, trailing: 0)
        manager.preferredCameraLayoutMargins = customBaseline
        manager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 40, leading: 32, bottom: 200, trailing: 32)

        manager.setBaseMapType(.hybrid)
        #expect(manager.mapView.directionalLayoutMargins == customBaseline)

        manager.preferredCameraLayoutMargins = .zero
        manager.setBaseMapType(.standard)
        #expect(manager.mapView.directionalLayoutMargins == .zero)
    }

    @Test func `MapBaseStyleDescriptor tracks cache keys and transition invalidation`() {
        let standard = MapBaseType.standard.styleDescriptor(showingPointsOfInterest: true)
        let satellite = MapBaseType.satellite.styleDescriptor(showingPointsOfInterest: true)
        let hybrid = MapBaseType.hybrid.styleDescriptor(showingPointsOfInterest: true)

        #expect(Set([standard.cacheIdentifier, satellite.cacheIdentifier, hybrid.cacheIdentifier]).count == 3)
        #expect(!standard.usesRasterImagery)
        #expect(satellite.usesRasterImagery)
        #expect(hybrid.usesRasterImagery)

        #expect(standard.requiresCacheInvalidation(transitioningTo: satellite))
        #expect(satellite.requiresCacheInvalidation(transitioningTo: hybrid))
        #expect(hybrid.requiresCacheInvalidation(transitioningTo: standard))
        #expect(!standard.requiresCacheInvalidation(transitioningTo: standard))
    }
}
