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

        let completion = BlockOperation { [weak self] in
            guard let mapView = self?.mapView else {
                return
            }

            let annotations = MapRegionManager.mapAnnotationsFromStops(requestStopsOperation.stops)
            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(annotations)

        }
        completion.addDependency(requestStopsOperation)

        OperationQueue.main.addOperation(completion)

        self.requestStopsOperation = requestStopsOperation
    }
}

extension MapRegionManager: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }
}

extension MapRegionManager: LocationServiceDelegate {
    private func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }
}

extension MapRegionManager {
    private class func mapAnnotationsFromStops(_ stops: [Stop]) -> [MKPointAnnotation] {
        return stops.map { (stop) -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = stop.location.coordinate
            annotation.title = stop.name
            annotation.subtitle = stop.direction
            return annotation
        }
    }
}
