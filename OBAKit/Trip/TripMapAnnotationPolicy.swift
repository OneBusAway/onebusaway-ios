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
/// highlights the matching list row. Programmatic selection on load is skipped
/// via `TripViewController.skipNextStopTimeHighlight` so opening a trip from a
/// departure does not immediately push that stop back on top of the trip.
enum TripMapAnnotationPolicy {
    static func apply(to view: MinimalStopAnnotationView) {
        view.canShowCallout = false
        view.rightCalloutAccessoryView = nil
        view.detailCalloutAccessoryView = nil
    }
}
