//
//  OnDemandZoneAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// The tappable marker at the centre of an on-demand zone. MapKit reports no
/// overlay taps, so this annotation is what routes a tap to the service page;
/// the polygon overlay is only the picture.
///
/// `nonisolated`: `MKAnnotation`'s requirements are nonisolated Objective-C
/// declarations, and every stored value here is immutable and `Sendable`.
nonisolated final class OnDemandZoneAnnotation: NSObject, MKAnnotation, Identifiable {
    let service: OnDemandService
    let coordinate: CLLocationCoordinate2D
    /// The service's route colour, resolved once when the layer draws it.
    let color: UIColor

    var title: String? { service.name }

    init(service: OnDemandService, coordinate: CLLocationCoordinate2D, color: UIColor) {
        self.service = service
        self.coordinate = coordinate
        self.color = color
        super.init()
    }
}
