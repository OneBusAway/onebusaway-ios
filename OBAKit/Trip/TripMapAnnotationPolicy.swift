//
//  TripMapAnnotationPolicy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// Callout behavior and marks for stop annotations on the trip map.
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

    /// Which of the trip map's pins stand out, and the arrival shown on one.
    ///
    /// The pins mark the rows the stop list marks, resolved by the same
    /// `TripStopListModel.riderStops`, so the map and the list cannot disagree
    /// about which stop is the rider's. See #449.
    ///
    /// Visual only. The trip map is hidden from VoiceOver, which reads the same
    /// marks from the stop list and the destination's arrival from the header.
    struct StopMarks {
        /// The trip's stop times in trip order, so a pin can find its row.
        var stopTimes: [TripStopTime] = []
        var riderStops = TripStopListModel.RiderStops(boardingIndex: nil, destinationIndex: nil)
        /// The shared destination's live arrival, or `nil` until it loads.
        var destinationArrival: ArrivalDeparture?

        func marking(for stopTime: TripStopTime) -> MinimalStopAnnotationView.Marking {
            // By row, not stop ID: a loop route calls at a stop more than once,
            // and only one of those calls is the rider's. A stop time's equality
            // includes its times, so each call finds its own row.
            guard let row = stopTimes.firstIndex(of: stopTime) else { return .ordinary }
            if row == riderStops.userStopIndex { return .riderStop }
            if row == riderStops.boardingMarkerIndex { return .boardingStop }
            return .ordinary
        }

        /// The shared destination's arrival, for the destination's pin and no other.
        func arrival(for stopTime: TripStopTime) -> ArrivalDeparture? {
            guard let destinationIndex = riderStops.destinationIndex,
                  stopTimes.firstIndex(of: stopTime) == destinationIndex else { return nil }
            return destinationArrival
        }
    }
}
