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

    /// Rebuilds `application` over a gate that holds the probes `gating` picks
    /// *after* their response is in hand, so a test can cancel the fetch between
    /// the network answering and the layer applying the result.
    private func holdProbes(gating: @escaping @Sendable (URLRequest) -> Bool = { OnDemandMapLayerTests.isProbe($0) }) -> GatedDataLoader {
        let gate = GatedDataLoader(dataLoader, gating: gating, holdsAfterResponse: true)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader, transport: gate)
        return gate
    }

    private nonisolated static func isProbe(_ request: URLRequest) -> Bool {
        request.url?.path.contains("/api/ondemand/services-for-location") ?? false
    }

    @Test func `Successful fetch draws one polygon and one marker per service at its label point`() async {
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
        let exterior = layer.services[0].areas[0].polygons[0][0]
        #expect(OnDemandGeometry.pointInRing(layer.annotations[0].coordinate, ring: exterior), "the pin sits inside its own polygon")
        let routeColor = layer.services[0].route?.color ?? layer.tintColor
        #expect(layer.annotations[0].color == routeColor, "the marker carries its service's colour")
        #expect(layer.zoneShapes.map(\.color) == [routeColor])
        #expect(layer.iconName == "car.fill")
    }

    /// A pan that finds the same services keeps what is drawn, so the panel's
    /// selected marker (tagged by annotation identity) survives it.
    @Test func `A refetch with the same services keeps the drawn zones`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        let firstOverlay = layer.overlays[0]
        let firstMarker = layer.annotations[0]

        layer.viewportDidChange(viewport.offsetBy(dx: 10_000, dy: 0))
        await layer.fetchTask?.value

        #expect(layer.overlays.count == 1)
        #expect(layer.overlays[0] === firstOverlay)
        #expect(layer.annotations[0] === firstMarker)
        #expect(mapView.overlays.count == 1, "the overlay was not re-added")
        #expect(mapView.annotations.filter { $0 is OnDemandZoneAnnotation }.count == 1)
    }

    /// Two services sharing one zone (Charlevoix's Dial-a-Ride and Medical
    /// Trips) stacked their pins on one point, so only one was visible.
    @Test func `Services sharing a zone get pins at least 50 metres apart`() async throws {
        let data = Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try #require(json["data"] as? [String: Any])
        var list = try #require(body["list"] as? [[String: Any]])
        var twin = list[0]
        twin["id"] = "5088_twin"
        twin["name"] = "Twin Service"
        list.append(twin)
        body["list"] = list
        json["data"] = body
        mockProbe(statusCode: 200, data: try JSONSerialization.data(withJSONObject: json))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.annotations.count == 2)
        let pins = Dictionary(uniqueKeysWithValues: layer.annotations.map { ($0.service.id, $0.coordinate) })
        let first = try #require(pins["5088_77652"])
        let second = try #require(pins["5088_twin"])
        let separation = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
        #expect(separation >= OnDemandGeometry.labelSeparationMeters, "pins \(separation) m apart")
        expectClose(first.latitude, (38.617508 + 39.057831) / 2, within: 1e-9)
        let exterior = layer.services[0].areas[0].polygons[0][0]
        #expect(OnDemandGeometry.pointInRing(second, ring: exterior), "the moved pin stays inside its polygon")
    }

    @Test func `A refetch with different services replaces the drawn zones`() async throws {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        let firstOverlay = layer.overlays[0]

        let viewportJSON = try #require(String(data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"), encoding: .utf8))
        let otherService = Data(viewportJSON.replacingOccurrences(of: "5088_77652", with: "5088_other").utf8)
        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: otherService) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
        }
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.services.map(\.id) == ["5088_other"])
        #expect(layer.overlays.count == 1)
        #expect(layer.overlays[0] !== firstOverlay)
        #expect(layer.annotations.map(\.service.id) == ["5088_other"])
        #expect(mapView.overlays.count == 1)
        #expect(mapView.overlays.first === layer.overlays[0])
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

    @Test func `An HTML 200 on the probe marks the layer unsupported`() async {
        dataLoader.mock(data: Data("<!doctype html><html><body>maglev</body></html>".utf8), contentType: "text/html; charset=utf-8", matcher: Self.isProbe)
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.availability == .unsupported, "the layers tile hides rather than dims")
        #expect(support.isKnownUnsupported(baseURL: serverBaseURL))
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

    /// Zooming out removes the zones but keeps the fetched services; a failure
    /// after zooming back in has nothing drawn to stand behind.
    @Test func `Server error after zooming out and back in dims the layer`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        layer.viewportDidChange(nil)

        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: Data(), statusCode: 500) { $0.url?.path.contains("/api/ondemand/services-for-location") ?? false }
        }
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        guard case .unavailable = layer.availability else {
            Issue.record("expected unavailable, got \(layer.availability)")
            return
        }
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

    @Test func `Deactivate clears drawn zones and ignores later viewports`() async {
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

    // MARK: - Zoom levels

    private let streetViewport = MKMapRect(
        origin: MKMapPoint(CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05)),
        size: MKMapSize(width: 30_000, height: 30_000)
    )

    @Test func `Zoom level is decided from the visible height`() {
        #expect(OnDemandZoomLevel.level(forVisibleHeight: 40_000) == .street)
        #expect(OnDemandZoomLevel.level(forVisibleHeight: 40_001) == .region)
        #expect(OnDemandZoomLevel.level(forVisibleHeight: 600_000) == .region)
        #expect(OnDemandZoomLevel.level(forVisibleHeight: 600_001) == .hidden)
        #expect(OnDemandZoomLevel.streetMaxVisibleHeight == MapRegionManager.requiredHeightToShowStops)
        #expect(layerZoomWindowMatchesRegionLevel())
    }

    private func layerZoomWindowMatchesRegionLevel() -> Bool {
        makeLayer().zoomWindow.maxVisibleHeight == OnDemandZoomLevel.regionMaxVisibleHeight
    }

    @Test func `Street level hides pins and draws a halo under a stroke-only polygon`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value

        #expect(layer.zoomLevel == .street)
        #expect(layer.annotations.isEmpty)
        #expect(!mapView.annotations.contains { $0 is OnDemandZoneAnnotation })
        #expect(layer.haloOverlays.count == 1)
        #expect(mapView.overlays.count == 2, "halo plus stroke")

        let stroke = layer.renderer(for: layer.overlays[0], in: mapView) as? MKPolygonRenderer
        #expect(stroke?.lineWidth == 4)
        var alpha: CGFloat = 1
        stroke?.fillColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        expectClose(Double(alpha), 0)

        let halo = layer.renderer(for: layer.haloOverlays[0], in: mapView) as? MKPolygonRenderer
        #expect(halo?.lineWidth == 10)
        halo?.strokeColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        expectClose(Double(alpha), 0.25)

        #expect(layer.zoneShapes.map(\.style) == [.halo, .street(emphasis: .normal)])
    }

    @Test func `Zooming back to region level restores pins and removes halos`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value

        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        #expect(layer.zoomLevel == .region)
        #expect(layer.annotations.count == 1)
        #expect(mapView.annotations.contains { $0 is OnDemandZoneAnnotation })
        #expect(mapView.overlays.count == 1)
        #expect(layer.zoneShapes.map(\.style) == [.region(highlighted: false)])
        let renderer = layer.renderer(for: layer.overlays[0], in: mapView) as? MKPolygonRenderer
        #expect(renderer?.lineWidth == 2)
    }

    @Test func `Highlight raises one service and dims the others at street level`() async throws {
        mockProbe(statusCode: 200, data: try Self.twoServicesResponse())
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value
        #expect(layer.services.map(\.id) == ["5088_77652", "5088_other"])

        layer.setHighlightedService("5088_other")
        #expect(layer.highlightedServiceID == "5088_other")
        // One polygon per service, in service order.
        func style(ofServiceAt index: Int) -> OnDemandZoneStyle? {
            let polygon = layer.overlays[index]
            return layer.zoneShapes.first { $0.polygon === polygon }?.style
        }
        #expect(style(ofServiceAt: 1) == .street(emphasis: .highlighted))
        #expect(style(ofServiceAt: 0) == .street(emphasis: .dimmed))

        var alpha: CGFloat = 1
        let dimmed = layer.renderer(for: layer.overlays[0], in: mapView) as? MKPolygonRenderer
        dimmed?.strokeColor?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        expectClose(Double(alpha), 0.6)

        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value
        let regionShapes = layer.zoneShapes.map(\.style)
        #expect(regionShapes.contains(.region(highlighted: true)))
        #expect(regionShapes.contains(.region(highlighted: false)))

        layer.setHighlightedService(nil)
        #expect(layer.zoneShapes.allSatisfy { $0.style == .region(highlighted: false) })
    }

    // MARK: - Overlay order

    private func zoneIndices(_ polygons: [MKPolygon], in mapView: MKMapView) -> [Int] {
        polygons.compactMap { polygon in mapView.overlays.firstIndex { $0 === polygon } }
    }

    /// Route- and trip-focus polylines share `.aboveRoads`; a restyle must not
    /// lift a zone's fill or halo over them.
    @Test func `Restyled zones stay beneath other overlays at their level`() async throws {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        var focusCoordinates = [CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05), CLLocationCoordinate2D(latitude: 38.84, longitude: -77.04)]
        let focusLine = MKPolyline(coordinates: &focusCoordinates, count: 2)
        mapView.addOverlay(focusLine, level: .aboveRoads)
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(viewport)
        await layer.fetchTask?.value

        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value
        layer.setHighlightedService("5088_77652")

        let focusIndex = try #require(mapView.overlays.firstIndex { $0 === focusLine })
        let zoneIndices = zoneIndices(layer.haloOverlays + layer.overlays, in: mapView)
        #expect(zoneIndices.count == 2)
        #expect(zoneIndices.allSatisfy { $0 < focusIndex })
    }

    @Test func `A service fetched on a later pan keeps its halo beneath every stroke`() async throws {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let layer = makeLayer()
        let mapView = MKMapView()
        layer.mapView = mapView
        layer.activate()
        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value

        let twoServices = try Self.twoServicesResponse()
        dataLoader.replaceMappedResponses { staging in
            staging.mock(data: twoServices) { Self.isProbe($0) }
        }
        layer.viewportDidChange(streetViewport)
        await layer.fetchTask?.value
        #expect(layer.services.count == 2)

        let haloIndices = zoneIndices(layer.haloOverlays, in: mapView)
        let strokeIndices = zoneIndices(layer.overlays, in: mapView)
        #expect(haloIndices.count == 2)
        #expect(strokeIndices.count == 2)
        #expect(try #require(haloIndices.max()) < #require(strokeIndices.min()))
    }

    /// The viewport fixture with its service duplicated as `5088_other`, which
    /// draws the same zone.
    private static func twoServicesResponse() throws -> Data {
        let viewportJSON = try #require(String(data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"), encoding: .utf8))
        let element = try #require(listElement(in: viewportJSON))
        let twoServices = viewportJSON.replacingOccurrences(
            of: "\"list\":[",
            with: "\"list\":[" + element.replacingOccurrences(of: "5088_77652", with: "5088_other") + ","
        )
        return Data(twoServices.utf8)
    }

    /// The JSON text of the fixture's single list element, for duplication.
    private nonisolated static func listElement(in json: String) -> String? {
        guard let start = json.range(of: "\"list\":[")?.upperBound,
              let end = json.range(of: "],\"outOfRange\"")?.lowerBound ?? json.range(of: "],\"references\"")?.lowerBound else {
            return nil
        }
        return String(json[start..<end])
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

    // MARK: - Cancellation

    /// The response has already arrived when the task is cancelled, so only the
    /// layer's own cancellation check stands between a 404 and `.unsupported`.
    @Test func `A failure landing after deactivate is ignored`() async {
        mockProbe(statusCode: 404)
        let gate = holdProbes()
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        let task = layer.fetchTask
        await gate.waitForRequest()

        layer.deactivate()
        gate.releaseRequest()
        await task?.value

        #expect(layer.availability == .available)
        #expect(layer.services.isEmpty)
    }

    /// Zooming out mid-fetch must stop the in-flight fetch from redrawing
    /// zones over a map that is now too far out to show them.
    @Test func `A fetch landing after a zoom-out draws nothing`() async {
        mockProbe(statusCode: 200, data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"))
        let gate = holdProbes()
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(viewport)
        let task = layer.fetchTask
        await gate.waitForRequest()

        layer.viewportDidChange(nil)
        gate.releaseRequest()
        await task?.value

        #expect(layer.overlays.isEmpty)
        #expect(layer.annotations.isEmpty)
    }

    /// The first fetch's services land after the second fetch has applied its
    /// own; a superseded fetch must never overwrite a newer one.
    @Test func `A superseded fetch never applies its services`() async throws {
        let viewportJSON = try #require(String(data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json"), encoding: .utf8))
        let staleData = Data(viewportJSON.replacingOccurrences(of: "5088_77652", with: "5088_stale").utf8)
        let firstViewport = viewport
        let secondViewport = viewport.offsetBy(dx: 0, dy: 100_000)
        let firstCenterLatitude = MKCoordinateRegion(firstViewport).center.latitude

        dataLoader.mock(data: staleData) { request in
            Self.isProbe(request, centeredAtLatitude: firstCenterLatitude)
        }
        dataLoader.mock(data: Fixtures.loadData(file: "ondemand_services_for_location_viewport.json")) { request in
            request.url?.path.contains("/api/ondemand/services-for-location") ?? false
        }

        // Only the first viewport's probe is held; the second answers at once.
        let gate = holdProbes { Self.isProbe($0, centeredAtLatitude: firstCenterLatitude) }
        let layer = makeLayer()
        layer.activate()
        layer.viewportDidChange(firstViewport)
        let firstTask = layer.fetchTask
        await gate.waitForRequest()

        layer.viewportDidChange(secondViewport)
        await layer.fetchTask?.value
        gate.releaseRequest()
        await firstTask?.value

        #expect(layer.services.map(\.id) == ["5088_77652"])
    }

    private nonisolated static func isProbe(_ request: URLRequest, centeredAtLatitude latitude: Double) -> Bool {
        guard let url = request.url, url.path.contains("/api/ondemand/services-for-location"),
              let latParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "lat" })?.value,
              let requestLatitude = Double(latParam) else {
            return false
        }
        return abs(requestLatitude - latitude) < 1e-6
    }
}
