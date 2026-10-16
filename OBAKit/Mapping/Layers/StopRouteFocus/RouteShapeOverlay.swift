//
//  RouteShapeOverlay.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

/// One route's drawn shape. Carries its identity so the layer's renderer can
/// style it without a side table.
///
/// Each route draws three times: a casing of the route color darkened underneath, the
/// route-colored core on top, and its direction chevrons over both; see `RouteLinePart`.
/// The casing is what keeps a route-colored line legible over the basemap, and `part`
/// is how the renderer tells them apart.
final class RouteShapeOverlay: MKPolyline {
    /// Matches the isolation of the nonisolated MKPolyline initializer it
    /// overrides — see VehicleAnnotation.swift for the established pattern.
    nonisolated override init() {
        super.init()
    }

    /// Assigned immediately after construction — `MKPolyline`'s initializers are
    /// imported class factories, so there is no init to thread these through.
    var routeID: RouteID = ""
    var part: RouteLinePart = .core

    var isCasing: Bool { part == .casing }

    static func make(coordinates: [CLLocationCoordinate2D], routeID: RouteID, part: RouteLinePart) -> RouteShapeOverlay {
        var coordinates = coordinates
        let overlay = RouteShapeOverlay(coordinates: &coordinates, count: coordinates.count)
        overlay.routeID = routeID
        overlay.part = part
        return overlay
    }
}
