//
//  MapPanelLayersModelLifecycleTests.swift
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
import UIKit
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

extension MapPanelLayersModelTests {

    private final class MockLifecycleMapLayer: NSObject, MapLayer {
        let id: String
        let title: String = "Mock Layer"
        let iconName: String = "circle"
        let tintColor: UIColor = .systemBlue
        let group: MapLayerGroup = .otherModes
        let isEnabledByDefault: Bool
        var availability: MapLayerAvailability
        let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
        let densityBudget: Int = 10
        let isClusterable: Bool = false
        let refreshPolicy: MapLayerRefreshPolicy = .static
        let staleAfter: Duration? = nil

        private(set) var activateCallCount = 0
        private(set) var deactivateCallCount = 0
        private(set) var forwardViewportCallCount = 0

        init(id: String, isEnabledByDefault: Bool = true, availability: MapLayerAvailability = .available) {
            self.id = id
            self.isEnabledByDefault = isEnabledByDefault
            self.availability = availability
        }

        func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
        func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
        func activate() { activateCallCount += 1 }
        func deactivate() { deactivateCallCount += 1 }
        func viewportDidChange(_ mapRect: MKMapRect?) { forwardViewportCallCount += 1 }
        func mapAnnotationsWereCleared() {}
    }

    @Test func `Reset to defaults updates points of interest before posting layer notifications`() {
        let manager = application.mapRegionManager
        manager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        manager.mapViewShowsPointsOfInterest = false

        final class Box: @unchecked Sendable {
            var poiDuringNotification: Bool?
            var notificationCount = 0
        }
        let box = Box()

        let token = NotificationCenter.default.addObserver(
            forName: .mapLayerEnabledStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                box.notificationCount += 1
                if box.poiDuringNotification == nil {
                    box.poiDuringNotification = manager.mapViewShowsPointsOfInterest
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.resetMapLayersToDefaults()

        #expect(box.notificationCount > 0)
        #expect(box.poiDuringNotification == true)
        #expect(manager.mapViewShowsPointsOfInterest == true)
        #expect(model.showsPointsOfInterest == true)
    }

    @Test func `Reset to defaults does not re-activate or forward viewport to unchanged layers`() {
        let manager = application.mapRegionManager

        let unchangedLayer = MockLifecycleMapLayer(id: "unchanged_layer", isEnabledByDefault: true)
        let changedLayer = MockLifecycleMapLayer(id: "changed_layer", isEnabledByDefault: true)

        manager.registerMapLayer(unchangedLayer)
        manager.registerMapLayer(changedLayer)
        defer {
            manager.removeMapLayer(id: unchangedLayer.id)
            manager.removeMapLayer(id: changedLayer.id)
        }

        #expect(unchangedLayer.activateCallCount == 1)
        #expect(unchangedLayer.forwardViewportCallCount == 1)
        #expect(changedLayer.activateCallCount == 1)
        #expect(changedLayer.forwardViewportCallCount == 1)

        manager.setMapLayerEnabled(false, id: changedLayer.id)
        #expect(changedLayer.deactivateCallCount == 1)

        let unchangedActivateBefore = unchangedLayer.activateCallCount
        let unchangedViewportBefore = unchangedLayer.forwardViewportCallCount
        let changedActivateBefore = changedLayer.activateCallCount
        let changedViewportBefore = changedLayer.forwardViewportCallCount

        final class Box: @unchecked Sendable {
            var postedNotificationLayerIDs: [String] = []
        }
        let box = Box()

        let token = NotificationCenter.default.addObserver(
            forName: .mapLayerEnabledStateDidChange,
            object: nil,
            queue: nil
        ) { note in
            let id = note.object as? String
            MainActor.assumeIsolated {
                if let id {
                    box.postedNotificationLayerIDs.append(id)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.resetMapLayersToDefaults()

        #expect(unchangedLayer.activateCallCount == unchangedActivateBefore)
        #expect(unchangedLayer.forwardViewportCallCount == unchangedViewportBefore)
        #expect(!box.postedNotificationLayerIDs.contains(unchangedLayer.id))

        #expect(changedLayer.activateCallCount == changedActivateBefore + 1)
        #expect(changedLayer.forwardViewportCallCount == changedViewportBefore + 1)
        #expect(box.postedNotificationLayerIDs.contains(changedLayer.id))
    }

    @Test func `Enabled layer count is independent of observer delivery order`() {
        let stub = MockLifecycleMapLayer(id: "observer_order_layer", isEnabledByDefault: true, availability: .available)
        application.mapRegionManager.registerMapLayer(stub)
        defer { application.mapRegionManager.removeMapLayer(id: stub.id) }

        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)
        let countWithStub = model.enabledLayerCount
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)

        stub.availability = .unsupported

        final class Box: @unchecked Sendable {
            var earlyObserverFired = false
            var countInEarlyObserver: Int?
        }
        let box = Box()

        let earlyObserver = NotificationCenter.default.addObserver(
            forName: .mapLayerAvailabilityDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                box.earlyObserverFired = true
                box.countInEarlyObserver = self.application.mapRegionManager.enabledMapLayerCount
            }
        }
        defer { NotificationCenter.default.removeObserver(earlyObserver) }

        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)

        #expect(box.earlyObserverFired)
        #expect(box.countInEarlyObserver == countWithStub - 1)
        #expect(model.enabledLayerCount == countWithStub - 1)
        #expect(model.visibilityState.enabledLayerCount == countWithStub - 1)
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub - 1)

        stub.availability = .available
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)
        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)
        #expect(model.enabledLayerCount == countWithStub)
    }
}
