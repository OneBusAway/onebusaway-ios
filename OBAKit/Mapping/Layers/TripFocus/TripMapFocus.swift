//
//  TripMapFocus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import MapKit
import OBAKitCore
import UIKit

/// The single channel between the trip page and whatever is drawing the map.
///
/// Mirrors `StopMapFocus`, and for the same reason: the page publishes one value
/// and the layer reads it, so there is no second path by which the two could
/// disagree about what is being shown. It is also what lets the same page hang
/// over the map tab's map or a standalone host's — neither is named here.
@MainActor
final class TripMapFocus: ObservableObject {

    /// Everything the map needs to draw one trip. A value, so a refresh is one
    /// assignment rather than a sequence of mutations the layer has to keep up
    /// with.
    struct Content {
        let tripID: String
        let routeColor: UIColor
        let routeType: Route.RouteType
        /// The trip's shape. Empty when the agency publishes none, in which case
        /// the stops and vehicle still draw.
        let shape: [CLLocationCoordinate2D]
        /// How far along the shape the vehicle is, or `nil` on a trip with no
        /// live position — in which case none of the line is drawn as spent,
        /// because nothing is known to have been travelled.
        let progress: Double?
        /// The same rows the list renders, so the dot on the map and the dot in
        /// the list can never disagree about which stops are behind the bus.
        let stops: [TripStopListModel.Row]
        let vehicle: TripStatus?
        /// Debug: beside an estimated marker, also draw where the feed put the
        /// vehicle. See `FeatureFlags.showsRawVehicleFixKey`.
        var showsReportedPositions = false
    }

    @Published private(set) var content: Content?

    /// Where the vehicle is estimated to be now, once a second; `nil` when it isn't
    /// estimated, and the map draws `content`'s reported position instead. Separate
    /// from `content` so a tick moves the marker without redrawing the trip.
    @Published private(set) var vehicleEstimate: VehicleEstimate?

    /// Where to cut the line while an estimate runs, so its gray-to-colored join
    /// stays at the marker on every tick; `nil` cuts it at `content.progress`.
    /// Both maps read it.
    @Published private(set) var estimatedSplitProgress: Double?

    func apply(_ content: Content?) {
        self.content = content
    }

    func applyVehicleEstimate(_ estimate: VehicleEstimate?) {
        vehicleEstimate = estimate
        let progress = estimate?.progress
        if progress != estimatedSplitProgress { estimatedSplitProgress = progress }
    }

    func clear() {
        content = nil
        vehicleEstimate = nil
        estimatedSplitProgress = nil
    }
}

/// What both maps derive from one trip — `TripFocusMapLayer` on the map tab's
/// `MKMapView`, `TripFocusMapDisplayModel` on the panel's SwiftUI `Map` — kept here
/// so the two cannot disagree about where the bus is or what the camera frames.
extension TripMapFocus.Content {

    /// The shape cut at the vehicle. No reported progress means nothing is known to
    /// have been travelled, so the whole shape counts as ahead rather than guessing
    /// at a split.
    ///
    /// - Parameter estimatedProgress: `TripMapFocus.estimatedSplitProgress`, which
    ///   overrides the reported progress while an estimate runs.
    func shapeSplit(estimatedProgress: Double? = nil) -> TripShapeSplit.Result {
        (estimatedProgress ?? progress).map {
            TripShapeSplit.split(coordinates: shape, atFraction: $0)
        } ?? TripShapeSplit.Result(spent: [], ahead: shape)
    }

    /// Debug: where the feed put the vehicle, for drawing beside an estimate.
    /// Empty unless `showsReportedPositions` and an estimate is running.
    func reportedPositions(isEstimating: Bool) -> [ReportedPosition] {
        guard isEstimating, showsReportedPositions, let vehicle else { return [] }
        return [
            vehicle.lastKnownLocation.map { ReportedPosition(kind: .lastKnownLocation, coordinate: $0.coordinate) },
            vehicle.position.map { ReportedPosition(kind: .serverPosition, coordinate: $0.coordinate) }
        ]
        .compactMap { $0 }
        .filter { !$0.coordinate.isNullIsland }
    }

    /// The vehicle's position, or `nil` when it has reported none it can be drawn at.
    var vehicleCoordinate: CLLocationCoordinate2D? {
        guard let vehicle, !vehicle.coordinate.isNullIsland else { return nil }
        return vehicle.coordinate
    }

    /// Frames the bus and the rider together, which is the comparison the page
    /// exists to support, plus the path between them where that fits. Falls back
    /// to the part of the trip still ahead when no vehicle position has been
    /// reported, and to the stops when there is no shape at all.
    ///
    /// - Parameter split: `shapeSplit`, passed in so the drawing and the camera
    ///   agree about which half of the shape is still ahead without cutting it twice.
    func framingRect(split: TripShapeSplit.Result, userLocation: CLLocationCoordinate2D?) -> MKMapRect? {
        if let rect = TripCameraFraming.rect(
            vehicle: vehicleCoordinate,
            userLocation: userLocation,
            corridor: TripCameraFraming.corridor(ahead: split.ahead, userLocation: userLocation)
        ) {
            return rect
        }

        // A one-point shape frames to nothing useful, so it falls through to the
        // stops the same way an empty one does.
        if split.ahead.count >= 2 {
            return TripCameraFraming.rect(of: split.ahead)
        }

        return TripCameraFraming.rect(of: stops.compactMap(\.coordinate))
    }
}
