//
//  VehicleAnnotation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/4/20.
//

import Foundation
import OBAKitCore
import MapKit

class VehicleAnnotation: MKPointAnnotation {
    // Matches the isolation of the nonisolated MKPointAnnotation initializer it overrides.
    nonisolated override init() {
        super.init()
    }

    init(tripStatus: TripStatus) {
        self.tripStatus = tripStatus
        super.init()
        updateAnnotation()
    }

    private func updateAnnotation() {
        self.title = tripStatus?.title ?? ""
        self.coordinate = tripStatus?.lastKnownLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var tripStatus: TripStatus? {
        didSet {
            updateAnnotation()
        }
    }
}
