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

    @Test func `Enabled layer count updates when manager getter is read before notification`() {
        let stub = MockLifecycleMapLayer(id: "manager_getter_layer", isEnabledByDefault: true, availability: .available)
        application.mapRegionManager.registerMapLayer(stub)
        defer { application.mapRegionManager.removeMapLayer(id: stub.id) }

        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)
        let countWithStub = model.enabledLayerCount
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)

        stub.availability = .unsupported

        // Read the getter before posting the notification
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub - 1)

        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)

        #expect(model.enabledLayerCount == countWithStub - 1)
        #expect(model.visibilityState.enabledLayerCount == countWithStub - 1)
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub - 1)

        stub.availability = .available
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)
        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)
        #expect(model.enabledLayerCount == countWithStub)
        #expect(model.visibilityState.enabledLayerCount == countWithStub)
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)
    }

    @Test func `Enabled layer count updates when panel refreshes while manager snapshot is stale`() {
        let stub = MockLifecycleMapLayer(id: "panel_refresh_layer", isEnabledByDefault: true, availability: .available)
        application.mapRegionManager.registerMapLayer(stub)
        defer { application.mapRegionManager.removeMapLayer(id: stub.id) }

        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: stub.id)
        let countWithStub = model.enabledLayerCount
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)

        stub.availability = .unsupported

        // Refresh panel availability while manager snapshot is still stale (without calling getter first)
        model.refresh()

        #expect(model.enabledLayerCount == countWithStub - 1)
        #expect(model.visibilityState.enabledLayerCount == countWithStub - 1)
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub - 1)

        stub.availability = .available
        // Without first calling the getter, refresh panel
        model.refresh()

        #expect(model.enabledLayerCount == countWithStub)
        #expect(model.visibilityState.enabledLayerCount == countWithStub)
        #expect(application.mapRegionManager.enabledMapLayerCount == countWithStub)
    }

    @Test func `Reset to defaults does not overwrite layer selection before its transition`() {
        let manager = application.mapRegionManager
        let layer1 = MockLifecycleMapLayer(id: "live_selection_layer1", isEnabledByDefault: true)
        let layer2 = MockLifecycleMapLayer(id: "live_selection_layer2", isEnabledByDefault: true)
        manager.registerMapLayer(layer1)
        manager.registerMapLayer(layer2)
        defer {
            manager.removeMapLayer(layer1)
            manager.removeMapLayer(layer2)
        }

        manager.setMapLayerEnabled(false, id: layer1.id)
        manager.setMapLayerEnabled(false, id: layer2.id)

        final class Box: @unchecked Sendable {
            var layer2EnabledDuringLayer1Transition: Bool?
        }
        let box = Box()

        let token = NotificationCenter.default.addObserver(
            forName: .mapLayerEnabledStateDidChange,
            object: nil,
            queue: nil
        ) { note in
            let id = note.object as? String
            MainActor.assumeIsolated {
                if id == layer1.id {
                    box.layer2EnabledDuringLayer1Transition = manager.isMapLayerEnabled(id: layer2.id)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.resetMapLayersToDefaults()

        #expect(box.layer2EnabledDuringLayer1Transition == false)
        #expect(manager.isMapLayerEnabled(id: layer1.id) == true)
        #expect(manager.isMapLayerEnabled(id: layer2.id) == true)
    }

    @Test func `Removal deactivates old layer instance even if replacement with same ID is registered`() {
        let manager = application.mapRegionManager
        let oldLayer = MockLifecycleMapLayer(id: "replacement_layer", isEnabledByDefault: true)
        let newLayer = MockLifecycleMapLayer(id: "replacement_layer", isEnabledByDefault: true)

        manager.registerMapLayer(oldLayer)
        #expect(oldLayer.activateCallCount == 1)

        manager.removeMapLayer(id: oldLayer.id)
        #expect(oldLayer.deactivateCallCount == 1)

        // Re-activate oldLayer to test removal of an active instance when replacement is registered
        oldLayer.activate()
        #expect(oldLayer.activateCallCount == 2)

        manager.registerMapLayer(newLayer)
        #expect(newLayer.activateCallCount == 1)

        // Remove old instance by instance reference
        manager.removeMapLayer(oldLayer)
        #expect(oldLayer.deactivateCallCount == 2)
        #expect(newLayer.deactivateCallCount == 0)
        #expect(manager.mapLayer(id: "replacement_layer") === newLayer)

        manager.removeMapLayer(newLayer)
        #expect(newLayer.deactivateCallCount == 1)
    }

    @Test func `Reset to defaults skips layer instance replaced during earlier callbacks`() {
        let manager = application.mapRegionManager
        let layer1 = MockLifecycleMapLayer(id: "reset_skip_1", isEnabledByDefault: true)
        let oldLayer2 = MockLifecycleMapLayer(id: "reset_skip_2", isEnabledByDefault: true)
        let newLayer2 = MockLifecycleMapLayer(id: "reset_skip_2", isEnabledByDefault: true)

        manager.registerMapLayer(layer1)
        manager.registerMapLayer(oldLayer2)
        defer {
            manager.removeMapLayer(layer1)
            manager.removeMapLayer(oldLayer2)
            manager.removeMapLayer(newLayer2)
        }

        manager.setMapLayerEnabled(false, id: layer1.id)
        manager.setMapLayerEnabled(false, id: oldLayer2.id)

        let token = NotificationCenter.default.addObserver(
            forName: .mapLayerEnabledStateDidChange,
            object: nil,
            queue: nil
        ) { note in
            let id = note.object as? String
            MainActor.assumeIsolated {
                if id == layer1.id {
                    manager.removeMapLayer(oldLayer2)
                    manager.registerMapLayer(newLayer2)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let old2ActivateBefore = oldLayer2.activateCallCount

        manager.resetMapLayersToDefaults()

        #expect(oldLayer2.activateCallCount == old2ActivateBefore)
    }
}
