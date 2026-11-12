//
//  RouteLanes.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore

/// One stop's routes, laid out across the streets they share so they draw side by
/// side rather than one on top of the other (#1569), and drawn at whatever zoom the
/// map is at.
///
/// Both maps draw a stop's routes from this: `StopRouteFocusMapLayer` on the map
/// tab's `MKMapView`, and `StopFocusMapDisplayModel` on the panel's SwiftUI `Map`.
/// The layout (`RouteLaneLayout`) is the expensive part and is done once, here; each
/// map then asks for coordinates at its own zoom, and comes back when
/// `needsRedraw(drawnAt:now:)` says its zoom has moved far enough.
struct RouteLanes {

    /// Screen points between neighboring lanes: an unfocused line and its casing, so
    /// neighbors touch without covering each other.
    static let laneWidth: CGFloat = StopRouteFocusMapLayer.Style.coreWidth + RouteArrowStyle.casingExtraWidth

    static let empty = RouteLanes(shapes: [:])

    private let shapes: [RouteID: [CLLocationCoordinate2D]]
    private let lines: [RouteID: RouteLaneLayout.Line]

    /// Routes moved off the middle of a street somewhere along them. Only these
    /// depend on the zoom.
    let sharedRouteIDs: Set<RouteID>

    /// - Parameter shapes: Each route's shape. Slots go in route ID order, not the
    ///   order the routes arrive in: arrival order follows the soonest departure,
    ///   which rolls over as buses leave, and would swap the lines' sides on a redraw.
    init(shapes: [RouteID: [CLLocationCoordinate2D]]) {
        self.shapes = shapes
        lines = RouteLaneLayout.lines(for: shapes.keys.sorted().compactMap { routeID in
            shapes[routeID].map { (routeID, $0) }
        })
        sharedRouteIDs = Set(lines.filter { $0.value.isShared }.keys)
    }

    /// The route's line, a lane to one side wherever it shares a street.
    ///
    /// - Parameter screenScale: Screen points per map point at the map's zoom, or
    ///   `nil` before the map has a size, when shared routes draw down the middle.
    /// - Returns: `nil` for a route with no shape.
    func coordinates(for routeID: RouteID, screenScale: CGFloat?) -> [CLLocationCoordinate2D]? {
        guard let shape = shapes[routeID] else { return nil }
        guard let line = lines[routeID], line.isShared else { return shape }
        let laneWidth = screenScale.map { Double(Self.laneWidth / $0) } ?? 0
        return line.offsetCoordinates(laneWidth: laneWidth)
    }

    /// Lanes stay put within a quarter of a zoom level, where they are still about a
    /// line's width apart; past that they are drawn again for the new zoom.
    ///
    /// - Parameters:
    ///   - drawnAt: The screen scale the lanes were last drawn at, if any.
    ///   - now: The map's screen scale now.
    static func needsRedraw(drawnAt: CGFloat?, now: CGFloat) -> Bool {
        guard let drawnAt else { return true }
        return abs(log2(now / drawnAt)) >= 0.25
    }
}
