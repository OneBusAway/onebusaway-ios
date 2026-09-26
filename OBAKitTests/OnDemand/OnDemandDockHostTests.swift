//
//  OnDemandDockHostTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import FloatingPanel
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

    @Test func `A full-height side panel puts the dock past the panel's trailing edge`() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let surface = UIView()
        let dock = UIView()
        container.addSubview(surface)
        container.addSubview(dock)

        let constraints = OnDemandDockPlacement.floatingLeading(maxWidth: OnDemandDockPlacement.floatingMaxWidth)
            .constraints(dockView: dock, safeArea: container.safeAreaLayoutGuide, surface: surface)

        let leading = try #require(constraints.first { $0.firstItem === dock && $0.firstAttribute == .leading })
        #expect(leading.secondItem === surface)
        #expect(leading.secondAttribute == .trailing)
        #expect(leading.constant == OnDemandDockPlacement.gutter)
        #expect(constraints.contains { $0.firstItem === dock && $0.firstAttribute == .width && $0.relation == .lessThanOrEqual && $0.constant == 360 })
    }

    // MARK: - Anchor (spec 3.8)

    private let plannerState = OnDemandDockState.planner(OnDemandPlannerResult(
        qualifying: [], hiddenCount: 0, originInsideMatches: [],
        origin: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2),
        destination: CLLocationCoordinate2D(latitude: 45.0, longitude: -84.7)
    ))

    @Test func `The planner card anchors to the planner panel and takes its placement`() {
        let anchoring = OnDemandDockAnchoring(dockState: plannerState, horizontalSizeClass: .regular, homePanelState: .full, plannerPanelState: .half)
        #expect(anchoring.anchorsToPlanner)
        #expect(anchoring.placement == .sidePanel(width: MapPanelLandscapeLayout.WidthSize), "a full home panel must not push the card past a full-width planner surface")
        #expect(!anchoring.isHidden)
    }

    @Test func `The planner card hides while the planner panel is full height`() {
        let full = OnDemandDockAnchoring(dockState: plannerState, horizontalSizeClass: .compact, homePanelState: .tip, plannerPanelState: .full)
        #expect(full.anchorsToPlanner)
        #expect(full.isHidden)

        let tip = OnDemandDockAnchoring(dockState: plannerState, horizontalSizeClass: .compact, homePanelState: .tip, plannerPanelState: .tip)
        #expect(!tip.isHidden)
    }

    @Test func `Without a planner panel or card the dock follows the home panel`() {
        let noPanel = OnDemandDockAnchoring(dockState: plannerState, horizontalSizeClass: .regular, homePanelState: .full, plannerPanelState: nil)
        #expect(!noPanel.anchorsToPlanner)
        #expect(noPanel.placement == .floatingLeading(maxWidth: OnDemandDockPlacement.floatingMaxWidth))
        #expect(!noPanel.isHidden)

        let hidden = OnDemandDockAnchoring(dockState: .hidden, horizontalSizeClass: .regular, homePanelState: .half, plannerPanelState: .full)
        #expect(!hidden.anchorsToPlanner)
        #expect(!hidden.isHidden)
    }

    @Test func `The planner panel observer reports every state change`() {
        var changes = 0
        let observer = TripPlannerPanelObserver { changes += 1 }
        observer.floatingPanelDidChangeState(FloatingPanelController())
        #expect(changes == 1)
    }

    // MARK: - Host sizing

    /// The Alexandria point fixture with its one service renamed.
    private func dockHost(serviceName: String) async throws -> OnDemandDockHostController {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let fixture = try #require(String(data: Fixtures.loadData(file: "ondemand_services_for_location_point.json"), encoding: .utf8))
        let renamed = fixture.replacingOccurrences(of: "\"name\":\"DOT Paratransit\",\"serviceKind\"", with: "\"name\":\"\(serviceName)\",\"serviceKind\"")
        dataLoader.mock(data: Data(renamed.utf8)) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
        dataLoader.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/service/") ?? false }
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)

        let controller = OnDemandProbeController.make(application: application)
        controller.mapDidSettle(center: CLLocationCoordinate2D(latitude: 38.8, longitude: -77.05), zoomLevel: .region)
        await controller.refreshTask?.value
        guard case .card = controller.dockState else {
            Issue.record("expected the zone card, got \(controller.dockState)")
            throw CancellationError()
        }
        return OnDemandDockHostController(controller: controller, actions: .none, serviceColors: { [:] })
    }

    @Test func `A long service name grows the docked card at phone width`() async throws {
        let width: CGFloat = 343
        let shortHost = try await dockHost(serviceName: "DOT Paratransit")
        let longHost = try await dockHost(serviceName: "City of Alexandria Department of Transportation Paratransit Service")
        let singleLine = shortHost.fittingHeight(forWidth: width)
        #expect(singleLine > 0)
        #expect(longHost.fittingHeight(forWidth: width) > singleLine)

        // Laid out at that width, the host takes the wrapped height.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 800))
        container.addSubview(longHost.view)
        NSLayoutConstraint.activate([
            longHost.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            longHost.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            longHost.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        container.layoutIfNeeded()
        container.layoutIfNeeded()
        #expect(longHost.view.bounds.height > singleLine)
        expectClose(Double(longHost.view.bounds.height), Double(longHost.fittingHeight(forWidth: width)), within: 0.5)
    }

    // MARK: - Zoom out (spec 3.4 Interactions)

    private func area(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) throws -> ServiceArea {
        try JSONDecoder().decode(ServiceArea.self, from: Data("{\"id\":\"a\",\"bbox\":[\(minLon),\(minLat),\(maxLon),\(maxLat)]}".utf8))
    }

    @Test func `A small zone zooms out to twice the street gate centred on the probe point`() throws {
        let tiny = try area(minLon: -85.201, minLat: 45.299, maxLon: -85.199, maxLat: 45.301)
        let probe = CLLocationCoordinate2D(latitude: 45.31, longitude: -85.21)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [tiny], probePoint: probe, viewportSize: CGSize(width: 400, height: 800)))
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
        // A viewport with the zone's own aspect ratio adds nothing to the fit.
        let viewport = CGSize(width: bbox.width, height: bbox.height)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [county], probePoint: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), viewportSize: viewport))
        expectClose(rect.height, bbox.height * 1.4, within: 1)
        expectClose(rect.width, bbox.width * 1.4, within: 1)
    }

    @Test func `A huge zone is clamped to nine tenths of the outer window`() throws {
        let huge = try area(minLon: -90, minLat: 40, maxLon: -80, maxLat: 50)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [huge], probePoint: CLLocationCoordinate2D(latitude: 45, longitude: -85), viewportSize: CGSize(width: 400, height: 800)))
        expectClose(rect.height, OnDemandCameraTargets.maximumZoomOutHeight, within: 1)
        #expect(OnDemandCameraTargets.zoomOutRect(areas: [], probePoint: CLLocationCoordinate2D(latitude: 45, longitude: -85), viewportSize: CGSize(width: 400, height: 800)) == nil)
    }

    /// `setVisibleMapRect` fits a rect to the map's aspect ratio, so a wide
    /// county on a tall phone grew past the 600,000 window and nothing drew.
    /// The target already carries the viewport's aspect, so the fit adds no height.
    @Test func `A wide zone on a tall phone stays inside the zones window`() throws {
        let county = try area(minLon: -85.39, minLat: 45.11, maxLon: -84.73, maxLat: 45.37)
        let phone = CGSize(width: 402, height: 874)
        let rect = try #require(OnDemandCameraTargets.zoomOutRect(areas: [county], probePoint: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2), viewportSize: phone))
        #expect(rect.height <= OnDemandCameraTargets.maximumZoomOutHeight + 1)
        #expect(rect.height < OnDemandZoomLevel.regionMaxVisibleHeight)
        expectClose(rect.width / rect.height, Double(phone.width / phone.height), within: 1e-6)
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

    // MARK: - Layer flag on a cold launch

    /// With no stored preference, `bool(forKey:)` reads false until the
    /// registrar registers the layer's `true` default; the dock must read the
    /// flag after that, or the card and bar never show until the tile is toggled.
    @Test func `A fresh launch with no stored layer preference enables the dock`() {
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("stops-for-location") ?? false
        }
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let key = MapRegionManager.mapLayerDefaultsKey(id: OnDemandMapLayer.layerID)
        application.userDefaults.removeObject(forKey: key)
        #expect(application.userDefaults.object(forKey: key) == nil, "precondition: no stored preference")

        let mapController = MapViewController(application: application)
        mapController.loadViewIfNeeded()

        #expect(mapController.onDemandProbeController.isLayerEnabled)
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
