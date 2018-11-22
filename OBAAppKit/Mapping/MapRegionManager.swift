//
//  MapRegionManager.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit
import OBANetworkingKit
import OBALocationKit

@objc(OBAMapRegionManager)
public class MapRegionManager: NSObject {

    private let application: Application

    private var regionChangeRequestTimer: Timer?

    @objc public let mapView = MKMapView(frame: .zero)

    //public weak var delegate: MKMapViewDelegate?

    private var requestStopsOperation: StopsModelOperation?

    @objc public init(application: Application) {
        self.application = application

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized

        super.init()

        application.locationService.addDelegate(self)

        mapView.delegate = self
    }

    deinit {
        application.locationService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        requestStopsOperation?.cancel()
    }

    @objc func requestDataForMapRegion(_ timer: Timer) {
        guard let modelService = application.restAPIModelService else {
            return
        }

        if let op = self.requestStopsOperation {
            op.cancel()
        }

        let requestStopsOperation = modelService.getStops(region: mapView.region)
        requestStopsOperation.then { [weak self] in
            guard let self = self else {
                return
            }

            let mapView = self.mapView

            let mapAnnotations = self.findInstalledMapAnnotations(type: MKPointAnnotation.self)
            var oldAnnotations: Set<MKPointAnnotation> = Set(mapAnnotations)
            var newAnnotations: Set<MKPointAnnotation> = NSSet(array: MapRegionManager.annotationsFromStops(requestStopsOperation.stops)) as! Set<MKPointAnnotation>

            let overlap = newAnnotations.intersection(oldAnnotations)
            oldAnnotations.subtract(overlap)
            newAnnotations.subtract(overlap)

            mapView.removeAnnotations(oldAnnotations.map {$0})
            mapView.addAnnotations(newAnnotations.map {$0})
        }

        self.requestStopsOperation = requestStopsOperation
    }
}

extension MapRegionManager: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    func findInstalledMapAnnotations<T>(type: T.Type) -> [T] where T: MKAnnotation {
        return mapView.annotations.compactMap {$0 as? T}
    }
}

extension MapRegionManager: LocationServiceDelegate {
    private func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }
}

extension MapRegionManager {
    private class func annotationsFromStops(_ stops: [Stop]) -> [MKPointAnnotation] {
        return stops.map { (stop) -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = stop.location.coordinate
            annotation.title = stop.name
            annotation.subtitle = stop.direction
            return annotation
        }
    }
}
