//
//  TripMapAnnotationPolicy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit

/// Callout behavior for stop annotations on the trip map.
///
/// Trip stop pins are selected to highlight the corresponding row in the trip
/// details list. Schedule-time callouts ("flags") obscure the vehicle annotation
/// and duplicate information already shown in the list and navigation bar.
enum TripMapAnnotationPolicy {
    static let showsStopCallout = false

    static func apply(to view: MinimalStopAnnotationView) {
        view.canShowCallout = showsStopCallout

        guard !showsStopCallout else { return }

        view.rightCalloutAccessoryView = nil
        view.detailCalloutAccessoryView = nil
    }
}
