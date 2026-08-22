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
/// Schedule-time callouts duplicated the trip list and obscured the vehicle.
/// Pins therefore have `canShowCallout = false`. A rider tap opens the stop
/// (the same gesture `StopAnnotationView` uses without a callout) and
/// highlights the matching list row. Programmatic selection (first load,
/// list → map) arms `skipNextStopTimeHighlight` so that `didSelect` does
/// not push the stop. A 30s refresh must not re-select the origin after
/// the rider has moved the pin.
enum TripMapAnnotationPolicy {
    static func apply(to view: MinimalStopAnnotationView) {
        view.canShowCallout = false
        view.rightCalloutAccessoryView = nil
        view.detailCalloutAccessoryView = nil
    }
}
