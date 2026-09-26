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
/// region change and draws each zone as an `MKPolygon` in its resolved colour
/// (spec 2.3). At region level the polygon is filled and one marker per
/// service sits at the service's label point; at street level the fill drops
/// out, the stroke thickens, a halo polygon is drawn under it and the markers
/// come off the map — the docked bar carries the status there. The UIKit map
/// draws through `mapView`; the SwiftUI panel reads `zoneShapes` and
/// `annotations` after `onMapContentDidChange`.
///
/// Follows `RentalLayerCoordinator` for availability: the first
/// `.requestNotFound` from the probe marks the server in `OnDemandSupport` and
/// the row disappears; any other failure dims the row only while nothing is
/// drawn, and the next region change retries.
@MainActor final class OnDemandMapLayer: NSObject, MapLayer {

    static let layerID = "on-demand-zones"

    private let application: Application

    /// Attached by `MapViewController` after registration; nil on the SwiftUI
    /// panel, which draws `zoneShapes` itself. Re-adds whatever is already
    /// loaded, because the first fetch usually lands before the host attaches.
    weak var mapView: MKMapView? {
        didSet {
            guard let mapView, mapView !== oldValue else { return }
            mapView.addOverlays(displayedOverlays, level: .aboveRoads)
            mapView.addAnnotations(annotations)
        }
    }

    private(set) var availability: MapLayerAvailability = .available
    private(set) var services: [OnDemandService] = []
    /// The stroke/fill polygons, one per drawn ring set, in service order.
    private(set) var overlays: [MKPolygon] = []
    /// Street-level halos, one per element of `overlays`, in the same order.
    private(set) var haloOverlays: [MKPolygon] = []
    /// The zoom level of the last viewport; decides the style (spec 2.2).
    private(set) var zoomLevel: OnDemandZoomLevel = .region
    /// The one service drawn emphasised (spec 2.3 Highlight).
    private(set) var highlightedServiceID: String?

    /// Every drawn service's markers, kept off the map at street level.
    private var drawnAnnotations: [OnDemandZoneAnnotation] = []

    /// Markers the map should show now: none at street level.
    var annotations: [OnDemandZoneAnnotation] {
        zoomLevel == .street ? [] : drawnAnnotations
    }

    private var colorByOverlay: [ObjectIdentifier: UIColor] = [:]
    private var serviceIDByOverlay: [ObjectIdentifier: String] = [:]
    private var haloOverlayIDs = Set<ObjectIdentifier>()
    private var drawnByServiceID: [String: DrawnService] = [:]

    private struct DrawnService {
        let overlays: [MKPolygon]
        let halos: [MKPolygon]
        let annotations: [OnDemandZoneAnnotation]
    }

    /// Called after the drawn zones or their styles change, for a host with no
    /// `MKMapView` (the SwiftUI panel) to re-read `zoneShapes` and `annotations`.
    var onMapContentDidChange: (() -> Void)?

    /// Each drawn polygon with its colour and style, halos first so the panel
    /// draws them underneath.
    var zoneShapes: [OnDemandZoneShape] {
        let halos = zoomLevel == .street ? haloOverlays.map { shape(for: $0) } : []
        return halos + overlays.map { shape(for: $0) }
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
    var iconName: String { "car.fill" }
    var tintColor: UIColor { ThemeColors.shared.brand }
    var group: MapLayerGroup { .transit }
    var isEnabledByDefault: Bool { true }
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: OnDemandZoomLevel.regionMaxVisibleHeight) }
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
        applyZoomLevel(OnDemandZoomLevel.level(forVisibleHeight: mapRect.height))
        fetch(region: MKCoordinateRegion(mapRect))
    }

    func mapAnnotationsWereCleared() {
        mapView?.addAnnotations(annotations)
    }

    func mapOverlaysWereCleared() {
        mapView?.addOverlays(displayedOverlays, level: .aboveRoads)
    }

    func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let color = colorByOverlay[ObjectIdentifier(polygon)] else {
            return nil
        }
        let style = style(for: polygon)
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = color.withAlphaComponent(style.fillAlpha)
        renderer.strokeColor = color.withAlphaComponent(style.strokeAlpha)
        renderer.lineWidth = style.lineWidth
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
        marker.titleVisibility = .visible
        marker.subtitleVisibility = .hidden
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

    // MARK: - Highlight

    /// Emphasises one service's polygons and dims the others' street strokes.
    /// Pass nil to clear.
    func setHighlightedService(_ serviceID: String?) {
        guard serviceID != highlightedServiceID else { return }
        highlightedServiceID = serviceID
        restyleOverlays()
    }

    // MARK: - Styles

    /// Everything the map should carry at the current level: halos under strokes at street level.
    private var displayedOverlays: [MKPolygon] {
        zoomLevel == .street ? haloOverlays + overlays : overlays
    }

    private func style(for polygon: MKPolygon) -> OnDemandZoneStyle {
        let identifier = ObjectIdentifier(polygon)
        if haloOverlayIDs.contains(identifier) { return .halo }
        let isHighlighted = highlightedServiceID != nil && serviceIDByOverlay[identifier] == highlightedServiceID
        switch zoomLevel {
        case .street:
            if isHighlighted { return .street(emphasis: .highlighted) }
            return highlightedServiceID == nil ? .street(emphasis: .normal) : .street(emphasis: .dimmed)
        case .region, .hidden:
            return .region(highlighted: isHighlighted)
        }
    }

    private func shape(for polygon: MKPolygon) -> OnDemandZoneShape {
        OnDemandZoneShape(polygon: polygon, color: colorByOverlay[ObjectIdentifier(polygon)] ?? tintColor, style: style(for: polygon))
    }

    private func applyZoomLevel(_ level: OnDemandZoomLevel) {
        guard level != zoomLevel else { return }
        let wasStreet = zoomLevel == .street
        zoomLevel = level
        if wasStreet != (level == .street) {
            mapView?.removeAnnotations(drawnAnnotations)
            mapView?.addAnnotations(annotations)
        }
        restyleOverlays()
    }

    /// MapKit caches renderers, so a style change re-adds the overlays.
    private func restyleOverlays() {
        if let mapView {
            mapView.removeOverlays(overlays + haloOverlays)
            mapView.addOverlays(displayedOverlays, level: .aboveRoads)
        }
        onMapContentDidChange?()
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
        let isNothingDrawn = overlays.isEmpty && drawnAnnotations.isEmpty
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

    /// Diffs the fetched services against what is drawn by id, so the panel's
    /// selected marker (tagged by annotation identity) survives a pan.
    private func reconcileMapContent() {
        let fetchedIDs = Set(services.map(\.id))
        let departedIDs = drawnByServiceID.keys.filter { !fetchedIDs.contains($0) }
        for serviceID in departedIDs {
            guard let drawn = drawnByServiceID.removeValue(forKey: serviceID) else { continue }
            mapView?.removeOverlays(drawn.overlays + drawn.halos)
            mapView?.removeAnnotations(drawn.annotations)
            for polygon in drawn.overlays + drawn.halos {
                let identifier = ObjectIdentifier(polygon)
                colorByOverlay[identifier] = nil
                serviceIDByOverlay[identifier] = nil
                haloOverlayIDs.remove(identifier)
            }
        }

        let colors = OnDemandServiceColors.resolvedColors(for: services, brand: tintColor)
        for service in services where drawnByServiceID[service.id] == nil {
            let drawn = draw(service, color: colors[service.id] ?? tintColor)
            drawnByServiceID[service.id] = drawn
            mapView?.addOverlays(zoomLevel == .street ? drawn.halos + drawn.overlays : drawn.overlays, level: .aboveRoads)
            if zoomLevel != .street {
                mapView?.addAnnotations(drawn.annotations)
            }
        }

        let drawnInOrder = services.compactMap { drawnByServiceID[$0.id] }
        overlays = drawnInOrder.flatMap(\.overlays)
        haloOverlays = drawnInOrder.flatMap(\.halos)
        drawnAnnotations = drawnInOrder.flatMap(\.annotations)
        onMapContentDidChange?()
    }

    /// Builds one service's polygons, their halo copies and its single marker
    /// at the label point of its largest polygon.
    private func draw(_ service: OnDemandService, color: UIColor) -> DrawnService {
        var polygons: [MKPolygon] = []
        var halos: [MKPolygon] = []
        for area in service.areas {
            for polygon in area.mkPolygons {
                let halo = MKPolygon(points: polygon.points(), count: polygon.pointCount, interiorPolygons: polygon.interiorPolygons)
                for drawnPolygon in [polygon, halo] {
                    colorByOverlay[ObjectIdentifier(drawnPolygon)] = color
                    serviceIDByOverlay[ObjectIdentifier(drawnPolygon)] = service.id
                }
                haloOverlayIDs.insert(ObjectIdentifier(halo))
                polygons.append(polygon)
                halos.append(halo)
            }
        }

        var markers: [OnDemandZoneAnnotation] = []
        if let coordinate = OnDemandGeometry.labelPoint(areas: service.areas) ?? service.areas.first?.bbox.center {
            markers.append(OnDemandZoneAnnotation(service: service, coordinate: coordinate, color: color))
        }
        return DrawnService(overlays: polygons, halos: halos, annotations: markers)
    }

    private func removeAllFromMap() {
        let wasDrawn = !overlays.isEmpty || !drawnAnnotations.isEmpty
        mapView?.removeOverlays(overlays + haloOverlays)
        mapView?.removeAnnotations(drawnAnnotations)
        overlays = []
        haloOverlays = []
        drawnAnnotations = []
        colorByOverlay = [:]
        serviceIDByOverlay = [:]
        haloOverlayIDs = []
        drawnByServiceID = [:]
        if wasDrawn {
            onMapContentDidChange?()
        }
    }
}

/// How a drawn zone polygon is painted (spec 2.3).
enum OnDemandZoneStyle: Equatable {
    enum StreetEmphasis: Equatable {
        case normal
        case highlighted
        /// Another service is highlighted.
        case dimmed
    }

    case region(highlighted: Bool)
    case street(emphasis: StreetEmphasis)
    /// The 10 pt, 25 % stroke drawn under a street-level polygon.
    case halo

    static let regionFillAlpha: CGFloat = 0.2
    static let regionLineWidth: CGFloat = 2
    static let emphasizedLineWidth: CGFloat = 4
    static let haloLineWidth: CGFloat = 10
    static let haloStrokeAlpha: CGFloat = 0.25
    static let dimmedStrokeAlpha: CGFloat = 0.6

    var fillAlpha: CGFloat {
        if case .region = self { return Self.regionFillAlpha }
        return 0
    }

    var lineWidth: CGFloat {
        switch self {
        case .region(let highlighted): return highlighted ? Self.emphasizedLineWidth : Self.regionLineWidth
        case .street: return Self.emphasizedLineWidth
        case .halo: return Self.haloLineWidth
        }
    }

    var strokeAlpha: CGFloat {
        switch self {
        case .halo: return Self.haloStrokeAlpha
        case .street(let emphasis): return emphasis == .dimmed ? Self.dimmedStrokeAlpha : 1
        case .region: return 1
        }
    }
}

/// One drawn zone polygon with the colour and style both surfaces paint it in.
struct OnDemandZoneShape: Identifiable {
    let polygon: MKPolygon
    let color: UIColor
    let style: OnDemandZoneStyle

    var id: ObjectIdentifier { ObjectIdentifier(polygon) }
}
