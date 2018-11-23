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

            var oldAnnotations = Set(mapView.annotations.compactMap {$0 as? Stop})
            var newAnnotations = Set(requestStopsOperation.stops)

            // Which elements are in both sets?
            let overlap = newAnnotations.intersection(oldAnnotations)

            // Remove the elements that no longer appear in the new set,
            // but leaving the ones that still appear.
            oldAnnotations.subtract(oldAnnotations.subtracting(overlap))
            newAnnotations.subtract(overlap)

            mapView.removeAnnotations(oldAnnotations.allObjects)
            mapView.addAnnotations(newAnnotations.allObjects)
        }

        self.requestStopsOperation = requestStopsOperation
    }
}

// MARK: - Map View Delegate

extension MapRegionManager: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    func findInstalledMapAnnotations<T>(type: T.Type) -> Set<T> where T: MKAnnotation {
        return Set(mapView.annotations.compactMap {$0 as? T})
    }
}

// MARK: - Location Service Delegate

extension MapRegionManager: LocationServiceDelegate {
    private func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }
}
