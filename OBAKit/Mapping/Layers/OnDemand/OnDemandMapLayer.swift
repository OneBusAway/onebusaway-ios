//
//  OnDemandMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// On-demand (GTFS-Flex) service zones on the main map.
///
/// Fetches `services-for-location` in the server's viewport mode on every map
/// region change and draws each zone as a filled `MKPolygon` in its route's
/// colour, with a marker at the zone's bounding-box centre that opens the
/// service page. The UIKit map draws through `mapView`; the SwiftUI panel
/// reads `zoneShapes` and `annotations` after `onMapContentDidChange`.
///
/// Follows `RentalLayerCoordinator` for availability: the first
/// `.requestNotFound` from the probe marks the server in `OnDemandSupport` and
/// the row disappears; any other failure dims the row only while nothing is
/// drawn, and the next region change retries.
@MainActor final class OnDemandMapLayer: NSObject, MapLayer {

    static let layerID = "on-demand-zones"

    private let application: Application

    /// Attached by `MapViewController` after registration; nil on the SwiftUI
    /// panel, which draws `zoneShapes` itself as `MapPolygon`s. Re-adds
    /// whatever is already loaded, because the first fetch usually lands
    /// before the host attaches.
    weak var mapView: MKMapView? {
        didSet {
            guard let mapView, mapView !== oldValue else { return }
            mapView.addOverlays(overlays, level: .aboveRoads)
            mapView.addAnnotations(annotations)
        }
    }

    private(set) var availability: MapLayerAvailability = .available
    private(set) var services: [OnDemandService] = []
    private(set) var overlays: [MKPolygon] = []
    private(set) var annotations: [OnDemandZoneAnnotation] = []
    /// Each drawn overlay's colour, by identity — the renderer claims only these.
    private var colorByOverlay: [ObjectIdentifier: UIColor] = [:]
    /// What each drawn service put on the map, so a refetch touches only the
    /// services that came or went.
    private var drawnByServiceID: [String: DrawnService] = [:]

    private struct DrawnService {
        let overlays: [MKPolygon]
        let annotations: [OnDemandZoneAnnotation]
    }

    /// Called after the drawn zones change, for a host with no `MKMapView`
    /// (the SwiftUI panel) to re-read `zoneShapes` and `annotations`.
    var onMapContentDidChange: (() -> Void)?

    /// Shared by both surfaces so the panel's zones match the UIKit map's.
    static let zoneFillAlpha: CGFloat = 0.2
    static let zoneLineWidth: CGFloat = 2

    /// Each drawn polygon with its colour, for the panel's `MapPolygon`s.
    var zoneShapes: [OnDemandZoneShape] {
        overlays.map { polygon in
            OnDemandZoneShape(polygon: polygon, color: colorByOverlay[ObjectIdentifier(polygon)] ?? tintColor)
        }
    }

    /// Exposed so tests can await the in-flight fetch instead of polling.
    private(set) var fetchTask: Task<Void, Never>?
    private var isActive = false

    /// Support is read from `application.apiService`, the only writer, so the
    /// layer and the probe can never consult different caches.
    init(application: Application) {
        self.application = application
        super.init()
    }

    // MARK: - MapLayer

    var id: String { Self.layerID }
    var title: String { Strings.onDemandZonesLayer }
    var iconName: String { "car.circle" }
    var tintColor: UIColor { ThemeColors.shared.brand }
    var group: MapLayerGroup { .transit }
    var isEnabledByDefault: Bool { true }

    /// Ten times the stop gate: county-sized zones must survive a zoomed-out map.
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: 400_000) }
    var densityBudget: Int { 50 }
    var isClusterable: Bool { false }
    var refreshPolicy: MapLayerRefreshPolicy { .onViewportChange }
    var staleAfter: Duration? { nil }

    func activate() {
        isActive = true
        refreshSupportState()
    }

    func deactivate() {
        isActive = false
        fetchTask?.cancel()
        fetchTask = nil
        removeAllFromMap()
        services = []
    }

    func viewportDidChange(_ mapRect: MKMapRect?) {
        guard isActive else { return }
        guard let mapRect else {
            // An in-flight fetch would otherwise redraw the zones it removed.
            fetchTask?.cancel()
            removeAllFromMap()
            return
        }
        guard availability != .unsupported else { return }
        fetch(region: MKCoordinateRegion(mapRect))
    }

    func mapAnnotationsWereCleared() {
        mapView?.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        mapView?.addOverlays(overlays, level: .aboveRoads)
    }

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let color = colorByOverlay[ObjectIdentifier(polygon)] else {
            return nil
        }
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = color.withAlphaComponent(Self.zoneFillAlpha)
        renderer.strokeColor = color
        renderer.lineWidth = Self.zoneLineWidth
        return renderer
    }

    private static let markerReuseIdentifier = "OnDemandZoneMarker"

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        guard let zone = annotation as? OnDemandZoneAnnotation else { return nil }
        let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: Self.markerReuseIdentifier) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.markerReuseIdentifier)
        marker.annotation = annotation
        marker.glyphImage = UIImage(systemName: "car.fill")
        marker.markerTintColor = zone.color
        marker.canShowCallout = false
        marker.displayPriority = .defaultLow
        return marker
    }

    /// Zones are ambient context, like rentals: they recede while a stop sheet
    /// owns the map. Recognizes exactly what `annotationView(for:in:)` claims.
    func recedesBehindStopSheet(_ annotation: MKAnnotation) -> Bool {
        annotation is OnDemandZoneAnnotation
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? {
        guard let zone = annotation as? OnDemandZoneAnnotation else { return nil }
        return OnDemandServiceViewController(application: application, service: zone.service)
    }

    // MARK: - Fetching

    private func fetch(region: MKCoordinateRegion) {
        guard let apiService = application.apiService else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            do {
                let response = try await apiService.getOnDemandServices(region: region, geometryDetail: .simplified)
                guard !Task.isCancelled else { return }
                self?.apply(services: response.list)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                self?.handle(error)
            }
        }
    }

    /// Not `private`: tests feed results straight in.
    func apply(services newServices: [OnDemandService]) {
        services = newServices.sorted { $0.id < $1.id }
        setAvailability(.available)
        reconcileMapContent()
    }

    /// Not `private`: tests feed failures straight in.
    func handle(_ error: Error) {
        if let apiError = error as? APIError, case .requestNotFound = apiError {
            // The service layer has already recorded the absence; mirror it here
            // so the row disappears without a second probe.
            removeAllFromMap()
            services = []
            setAvailability(.unsupported)
            return
        }

        Logger.error("On-demand zones fetch failed: \(error)")
        // Asks what is drawn, not what was fetched: a zoomed-out viewport
        // removes the zones but keeps `services`, and a live row over an
        // empty map would say "there is nothing here".
        let isNothingDrawn = overlays.isEmpty && annotations.isEmpty
        if isNothingDrawn {
            setAvailability(.unavailable(reason: Strings.onDemandZonesUnavailable))
        }
    }

    /// Reads `OnDemandSupport` for the current server. Called on activate; the
    /// registrar rebuilds this layer on region change, so a new region starts
    /// here again. With no REST service yet, support is unknown, not absent.
    private func refreshSupportState() {
        if let apiService = application.apiService,
           apiService.onDemandSupport.isKnownUnsupported(baseURL: apiService.baseURL) {
            setAvailability(.unsupported)
        } else if availability == .unsupported {
            setAvailability(.available)
        }
    }

    private func setAvailability(_ newValue: MapLayerAvailability) {
        guard availability != newValue else { return }
        availability = newValue
        NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: id)
    }

    // MARK: - Map content

    /// Diffs the fetched services against what is drawn by id: services that
    /// left the viewport come off the map, new ones go on, and the rest keep
    /// their overlays and annotations — so the panel's selected marker, which
    /// is tagged by annotation identity, survives a pan.
    private func reconcileMapContent() {
        let fetchedIDs = Set(services.map(\.id))
        let departedIDs = drawnByServiceID.keys.filter { !fetchedIDs.contains($0) }
        for serviceID in departedIDs {
            guard let drawn = drawnByServiceID.removeValue(forKey: serviceID) else { continue }
            mapView?.removeOverlays(drawn.overlays)
            mapView?.removeAnnotations(drawn.annotations)
            for polygon in drawn.overlays {
                colorByOverlay[ObjectIdentifier(polygon)] = nil
            }
        }

        for service in services where drawnByServiceID[service.id] == nil {
            let drawn = draw(service)
            drawnByServiceID[service.id] = drawn
            mapView?.addOverlays(drawn.overlays, level: .aboveRoads)
            mapView?.addAnnotations(drawn.annotations)
        }

        let drawnInOrder = services.compactMap { drawnByServiceID[$0.id] }
        overlays = drawnInOrder.flatMap(\.overlays)
        annotations = drawnInOrder.flatMap(\.annotations)
        onMapContentDidChange?()
    }

    /// Builds one service's polygons and zone markers, in its route colour.
    private func draw(_ service: OnDemandService) -> DrawnService {
        let color = service.route?.color ?? tintColor
        var polygons: [MKPolygon] = []
        var markers: [OnDemandZoneAnnotation] = []
        for area in service.areas {
            for polygon in area.mkPolygons {
                colorByOverlay[ObjectIdentifier(polygon)] = color
                polygons.append(polygon)
            }
            markers.append(OnDemandZoneAnnotation(service: service, coordinate: area.bbox.center, color: color))
        }
        return DrawnService(overlays: polygons, annotations: markers)
    }

    private func removeAllFromMap() {
        let wasDrawn = !overlays.isEmpty || !annotations.isEmpty
        mapView?.removeOverlays(overlays)
        mapView?.removeAnnotations(annotations)
        overlays = []
        annotations = []
        colorByOverlay = [:]
        drawnByServiceID = [:]
        if wasDrawn {
            onMapContentDidChange?()
        }
    }
}

/// One drawn zone polygon and the colour both surfaces paint it in.
struct OnDemandZoneShape: Identifiable {
    let polygon: MKPolygon
    let color: UIColor

    var id: ObjectIdentifier { ObjectIdentifier(polygon) }
}
