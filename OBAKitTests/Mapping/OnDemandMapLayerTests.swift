//
//  OnDemandMapLayerTests.swift
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

@MainActor
@Suite(.serialized)
final class OnDemandMapLayerTests: OBATestCase {

    private var application: Application!
    private var dataLoader: MockDataLoader!

    /// A ~50 km viewport over Alexandria.
    private let viewport = MKMapRect(
        origin: MKMapPoint(CLLocationCoordinate2D(latitude: 39.1, longitude: -77.6)),
        size: MKMapSize(width: 600_000, height: 600_000)
    )

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
    }

    /// The instance the REST service records into — the one the layer reads.
    private var support: OnDemandSupport { application.apiService!.onDemandSupport }

    private func makeLayer() -> OnDemandMapLayer {
        OnDemandMapLayer(application: application)
    }

    private func mockProbe(statusCode: Int, data: Data = Data()) {
        dataLoader.mock(data: data, statusCode: statusCode) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }
    }

    private var serverBaseURL: URL { application.apiService!.baseURL }

    @Test func `Successful fetch draws one polygon and one marker per area`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .available)
        #expect(layer.services.map(\.id) == ["5088_77652"])
        #expect(layer.overlays.count == 1)
        #expect(layer.annotations.count == 1)
        #expect(layer.annotations[0].title == "DOT Paratransit")
        expectClose(layer.annotations[0].coordinate.latitude, (38.617508 + 39.057831) / 2)
    }

    @Test func `404 on the probe marks the layer unsupported and empties it`() async {
        mockProbe(statusCode: 404)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .unsupported)
        #expect(layer.overlays.isEmpty)
        #expect(support.isKnownUnsupported(baseURL: serverBaseURL))
        #expect(!OnDemandSupport.shared.isKnownUnsupported(baseURL: serverBaseURL), "the probe must not taint the process-wide cache")
    }

    @Test func `Server error with nothing drawn dims the layer`() async {
        mockProbe(statusCode: 500)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        guard case .unavailable = layer.availability else {
            Issue.record("expected unavailable, got \(layer.availability)")
            return
        }
        #expect(!support.isKnownUnsupported(baseURL: serverBaseURL))
    }

    @Test func `Server error after a success keeps the drawn zones and stays available`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(layer.overlays.count == 1)

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
        }
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .available)
        #expect(layer.overlays.count == 1)
    }

    @Test func `A known-unsupported server is unsupported on activate and never fetches`() {
        support.recordAbsent(baseURL: serverBaseURL)
        let layer = makeLayer()
        layer.activate()
        #expect(layer.availability == .unsupported)

        layer.viewportDidChange(viewport)
        #expect(layer.fetchTask == nil)
        #expect(dataLoader.recordedRequestURLs.allSatisfy { !$0.path.contains("/api/ondemand") })
    }

    @Test func `Nil viewport removes overlays without refetching`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(layer.overlays.count == 1)

        dataLoader.resetRecordedRequestURLs()
        layer.viewportDidChange(nil)
        #expect(layer.overlays.isEmpty)
        #expect(layer.annotations.isEmpty)
        #expect(dataLoader.recordedRequestURLs.isEmpty)
    }

    @Test func `Deactivate cancels and clears`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        layer.deactivate()
        #expect(layer.services.isEmpty)
        #expect(layer.overlays.isEmpty)

        layer.viewportDidChange(viewport)
        #expect(layer.fetchTask == nil, "an inactive layer ignores viewports")
    }

    @Test func `Renderer claims only its own polygons and fills at 20 percent`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let mapView = MKMapView()
        let renderer = layer.renderer(for: layer.overlays[0], in: mapView) as? MKPolygonRenderer
        #expect(renderer != nil)
        #expect(renderer?.lineWidth == 2)
        var alpha: CGFloat = 0
        renderer?.fillColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        expectClose(Double(alpha), 0.2)

        let foreign = MKPolygon(coordinates: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 1, longitude: 0), CLLocationCoordinate2D(latitude: 1, longitude: 1)], count: 3)
        #expect(layer.renderer(for: foreign, in: mapView) == nil)
    }

    @Test func `Detail controller is the service page for a zone marker`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let controller = layer.detailViewController(for: layer.annotations[0])
        #expect(controller is OnDemandServiceViewController)
        #expect(controller?.title == "DOT Paratransit")
        #expect(layer.detailViewController(for: MKPointAnnotation()) == nil)
        #expect(layer.recedesBehindStopSheet(layer.annotations[0]))
        #expect(!layer.recedesBehindStopSheet(MKPointAnnotation()))
    }

    @Test func `Availability change posts the layer notification`() async {
        mockProbe(statusCode: 404)
        let layer = makeLayer()
        layer.activate()

        // `queue: nil` delivers synchronously on the posting (main) thread.
        let posted = SendableBox<[String]>([])
        let observer = NotificationCenter.default.addObserver(forName: .mapLayerAvailabilityDidChange, object: nil, queue: nil) { note in
            if let id = note.object as? String { posted.value.append(id) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(posted.value.contains(OnDemandMapLayer.layerID))
    }

    @Test func `Attaching a map view late re-adds what is already loaded`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let mapView = MKMapView()
        layer.mapView = mapView
        #expect(mapView.overlays.count == 1)
        #expect(mapView.annotations.contains { $0 is OnDemandZoneAnnotation })
    }

    @Test func `Marker view is claimed only for zone annotations`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        let mapView = MKMapView()
        let marker = layer.annotationView(for: layer.annotations[0], in: mapView) as? MKMarkerAnnotationView
        #expect(marker != nil)
        #expect(marker?.canShowCallout == false)
        #expect(layer.annotationView(for: MKPointAnnotation(), in: mapView) == nil)
    }

    /// Support is per server: a layer that learned one server lacks the
    /// namespace becomes available again when activated against another.
    @Test func `Activating against a different server clears unsupported`() async {
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)
        mockProbe(statusCode: 404)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        #expect(layer.availability == .unsupported)

        application.regionsService.currentRegion = Fixtures.tampaRegion
        layer.activate()
        #expect(layer.availability == .available)
    }
}
