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
    }

    @Published private(set) var content: Content?

    func apply(_ content: Content?) {
        self.content = content
    }

    func clear() {
        content = nil
    }
}
