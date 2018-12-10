//
//  MapRegionManager.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit

@objc(OBAMapRegionDelegate)
public protocol MapRegionDelegate {
    @objc optional func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop])
    @objc optional func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    @objc optional func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)
}

@objc(OBAMapRegionManager)
public class MapRegionManager: NSObject {

    private let application: Application

    private var regionChangeRequestTimer: Timer?

    @objc public let mapView = MKMapView()

    @objc public init(application: Application) {
        self.application = application

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized

        super.init()

        application.locationService.addDelegate(self)

        mapView.delegate = self

        addStatusOverlayToMap()
    }

    deinit {
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        requestStopsOperation?.cancel()
    }

    @objc func requestDataForMapRegion(_ timer: Timer) {
        guard let modelService = application.restAPIModelService else {
            return
        }

        self.requestStopsOperation?.cancel()
        self.requestStopsOperation = nil

        let requestStopsOperation = modelService.getStops(region: mapView.region)
        requestStopsOperation.then { [weak self] in
            guard let self = self else {
                return
            }

            self.stops = requestStopsOperation.stops
        }

        self.requestStopsOperation = requestStopsOperation
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<MapRegionDelegate>.weakObjects()

    @objc
    public func addDelegate(_ delegate: MapRegionDelegate) {
        delegates.add(delegate)
    }

    @objc
    public func removeDelegate(_ delegate: MapRegionDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesStopsChanged() {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, stopsUpdated: stops)
        }
    }

    // MARK: - Stops

    private var requestStopsOperation: StopsModelOperation?

    public private(set) var stops = [Stop]() {
        didSet {
            mapView.updateAnnotations(with: stops)
            notifyDelegatesStopsChanged()
        }
    }

    public func stopWithID(_ id: String, completion: @escaping (Stop?) -> Void) {
        if let stop = (stops.filter {$0.id == id}).first {
            completion(stop)
            return
        }

        guard let modelService = application.restAPIModelService else {
            return
        }

        let op = modelService.getStop(id: id)
        op.then {
            completion(op.stops.first)
        }
    }

    // MARK: - Overlays

    private var walkingDirectionsOverlay: MKOverlay?
    private var walkingDirectionsStop: Stop?

    public func addOverlay(_ overlay: MKOverlay, for stop: Stop) {
        if let walkingDirectionsOverlay = walkingDirectionsOverlay {
            mapView.removeOverlay(walkingDirectionsOverlay)
        }

        walkingDirectionsOverlay = overlay
        walkingDirectionsStop = stop

        mapView.addOverlay(walkingDirectionsOverlay!, level: MKOverlayLevel.aboveRoads)
    }

    // MARK: - Map Status Overlay

    private func addStatusOverlayToMap() {
        mapView.addSubview(statusOverlay)

        NSLayoutConstraint.activate([
            statusOverlay.centerXAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.centerXAnchor),
            statusOverlay.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: application.theme.metrics.padding)
        ])
    }

    private lazy var statusOverlay = StatusOverlayView.autolayoutNew()

    private static let requiredHeightToShowStops = 75000.0

    private func updateZoomWarningOverlay(mapHeight: Double) {
        if mapHeight > MapRegionManager.requiredHeightToShowStops {
            let message = NSLocalizedString("map_region_manager.status_overlay.zoom_to_see_stops", value: "Zoom in to look for stops", comment: "Map region manager message to the user when they need to zoom in more to view stops")
            statusOverlay.showOverlay(message: message)
        }
        else {
            statusOverlay.hideOverlay()
        }
    }
}

// MARK: - Map View Delegate

extension MapRegionManager: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        updateZoomWarningOverlay(mapHeight: mapView.visibleMapRect.height)

        guard mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops else {
            return
        }

        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        for delegate in delegates.allObjects {
            delegate.mapView?(mapView, didSelect: view)
        }
    }

    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        for delegate in delegates.allObjects {
            delegate.mapView?(mapView, didDeselect: view)
        }
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
        renderer.strokeColor = application.theme.colors.primary.withAlphaComponent(0.75)
        renderer.lineWidth = 6.0
        renderer.lineCap = .round

        return renderer
    }
}

// MARK: - Location Service Delegate

extension MapRegionManager: LocationServiceDelegate {
    private func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }
}
