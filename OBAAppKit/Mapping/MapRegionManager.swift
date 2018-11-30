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

@objc(OBAMapRegionDelegate)
public protocol MapRegionDelegate {
    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop])
}

@objc(OBAMapRegionManager)
public class MapRegionManager: NSObject {

    private let application: Application

    private var regionChangeRequestTimer: Timer?

    @objc public let mapView = MKMapView(frame: .zero)

    //public weak var delegate: MKMapViewDelegate?

    private var requestStopsOperation: StopsModelOperation?

    public private(set) var stops = [Stop]() {
        didSet {
            mapView.updateAnnotations(with: stops)
            notifyDelegatesStopsChanged()
        }
    }

    @objc public init(application: Application) {
        self.application = application

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized

        super.init()

        application.locationService.addDelegate(self)

        mapView.delegate = self
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
            delegate.mapRegionManager(self, stopsUpdated: stops)
        }
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
