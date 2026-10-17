//
//  MapViewControllerAccessibilityOrderTests.swift
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

/// VoiceOver order on the classic map. The map is the first subview, so its
/// annotations, which can be well over a hundred bikes and scooters downtown,
/// came before the status pill, the toolbar and the nearby-stops panel.
@MainActor
@Suite(.serialized)
final class MapViewControllerAccessibilityOrderTests: OBATestCase {

    private var application: Application!

    override init() async throws {
        try await super.init()
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
    }

    private func elements(of controller: MapViewController) -> [UIView] {
        (controller.view.accessibilityElements ?? []).compactMap { $0 as? UIView }
    }

    @Test func `The map comes after the panel, toolbar and status pill`() throws {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()

        let order = elements(of: controller)
        let firstMap = try #require(order.firstIndex { $0 is MKMapView })
        #expect(order[firstMap...].allSatisfy { $0 is MKMapView })
        #expect(order.contains(controller.mapRegionManager.mapView))

        for view: UIView in [controller.floatingPanel.view!, controller.toolbar, controller.mapStatusView] {
            let index = try #require(order.firstIndex(of: view))
            #expect(index < firstMap)
        }
    }

    /// The order is worked out when VoiceOver asks, so a view added later, such
    /// as a survey card or a semi-modal panel, isn't left out.
    @Test func `Views added after load are still in the order`() {
        let controller = MapViewController(application: application)
        controller.loadViewIfNeeded()

        let late = UIView()
        controller.view.addSubview(late)

        let order = elements(of: controller)
        #expect(order.contains(late))
        #expect(order.last is MKMapView)
    }
}
