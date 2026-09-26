//
//  OnDemandDockHostTests.swift
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
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandDockHostTests: OBATestCase {

    // MARK: - Placement (spec 2.4 Regular width and landscape)

    @Test func `Compact width docks full width above the sheet`() {
        #expect(OnDemandDockPlacement.placement(horizontalSizeClass: .compact, isPanelFullHeight: false) == .compact)
        #expect(OnDemandDockPlacement.placement(horizontalSizeClass: .compact, isPanelFullHeight: true) == .compact)
    }

    @Test func `Regular width takes the side panel's width unless the panel is full height`() {
        #expect(OnDemandDockPlacement.placement(horizontalSizeClass: .regular, isPanelFullHeight: false) == .sidePanel(width: MapPanelLandscapeLayout.WidthSize))
        #expect(OnDemandDockPlacement.placement(horizontalSizeClass: .regular, isPanelFullHeight: true) == .floatingLeading(maxWidth: 360))
    }

    // MARK: - Zoom out (spec 3.4 Interactions)

    private func area(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) throws -> ServiceArea {
        try JSONDecoder().decode(ServiceArea.self, from: Data("{\"id\":\"a\",\"bbox\":[\(minLon),\(minLat),\(maxLon),\(maxLat)]}".utf8))
    }

    @Test func `A small zone zooms out to twice the street gate centred on the probe point`() throws {
        let tiny = try area(minLon: -85.201, minLat: 45.299, maxLon: -85.199, maxLat: 45.301)
        let probe = CLLocationCoordinate2D(latitude: 45.31, longitude: -85.21)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [tiny], probePoint: probe))
        expectClose(rect.height, OnDemandCameraTargets.minimumZoomOutHeight, within: 1)
        let centre = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        expectClose(centre.latitude, probe.latitude, within: 1e-6)
        expectClose(centre.longitude, probe.longitude, within: 1e-6)
    }

    @Test func `A county-sized zone fits with 20 percent padding`() throws {
        let county = try area(minLon: -85.39, minLat: 45.11, maxLon: -84.73, maxLat: 45.37)
        let bbox = MKMapRect(
            origin: MKMapPoint(CLLocationCoordinate2D(latitude: 45.37, longitude: -85.39)),
            size: MKMapSize(width: MKMapPoint(CLLocationCoordinate2D(latitude: 45.37, longitude: -84.73)).x - MKMapPoint(CLLocationCoordinate2D(latitude: 45.37, longitude: -85.39)).x,
                            height: MKMapPoint(CLLocationCoordinate2D(latitude: 45.11, longitude: -85.39)).y - MKMapPoint(CLLocationCoordinate2D(latitude: 45.37, longitude: -85.39)).y)
        )
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [county], probePoint: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)))
        expectClose(rect.height, bbox.height * 1.4, within: 1)
        expectClose(rect.width, bbox.width * 1.4, within: 1)
    }

    @Test func `A huge zone is clamped to nine tenths of the outer window`() throws {
        let huge = try area(minLon: -90, minLat: 40, maxLon: -80, maxLat: 50)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [huge], probePoint: CLLocationCoordinate2D(latitude: 45, longitude: -85)))
        expectClose(rect.height, OnDemandCameraTargets.maximumZoomOutHeight, within: 1)
        #expect(OnDemandCameraTargets.zoomOutRect(areas: [], probePoint: CLLocationCoordinate2D(latitude: 45, longitude: -85)) == nil)
    }

    // MARK: - Viewport settle delegate

    private final class SettleSpy: NSObject, MapRegionDelegate {
        var rects: [MKMapRect] = []
        func mapRegionManager(_ manager: MapRegionManager, viewportDidSettle rect: MKMapRect) {
            rects.append(rect)
        }
    }

    @Test func `The region manager tells delegates when the viewport settles`() {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        // A region change also reloads stops; the unhosted map view's world
        // rect is outside the stop gate, but stub the request in case.
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("stops-for-location") ?? false
        }
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let spy = SettleSpy()
        application.mapRegionManager.addDelegate(spy)

        application.mapRegionManager.mapView(application.mapRegionManager.mapView, regionDidChangeAnimated: false)

        #expect(spy.rects.count == 1)
    }

    // MARK: - Factory

    @Test func `The application factory wires location and region delegates`() {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let controller = OnDemandProbeController.make(application: application)
        #expect(controller.currentDeployment == application.apiService?.baseURL.absoluteString)
        #expect(application.locationService.delegates.contains(controller))
    }
}
