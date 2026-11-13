//
//  MapPanelCameraCompensation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI

/// Keeps the panel's map still when its bottom padding changes because a sheet
/// settled at another detent.
///
/// The map's padding follows the tallest sheet (`MapPanelBottomPadding`). When it
/// changes, MapKit fits a position the app set (a region or a rect) into the new
/// visible area, which zooms and moves the whole map. A map the rider panned
/// stays put. So, for a change nobody asked for, the panel hands MapKit the camera
/// it last settled on instead, with its centre moved to where the visible area's
/// centre now is.
enum MapPanelCameraCompensation {

    /// Where the camera last settled, recorded together so they can't disagree.
    struct Settle: Equatable {
        let camera: MapCamera
        /// The map's scale: the visible map rect's width over the map view's.
        let mapPointsPerScreenPoint: Double
        /// The position that put the camera there.
        let position: MapCameraPosition
    }

    /// The position to hand MapKit when the bottom padding changes by
    /// `paddingDelta` points, or `nil` to let MapKit fit the current one.
    static func compensatedPosition(for position: MapCameraPosition, settle: Settle?, paddingDelta: CGFloat) -> MapCameraPosition? {
        guard paddingDelta != 0, let settle, compensates(position: position, positionAtSettle: settle.position) else {
            return nil
        }
        let camera = settle.camera
        return .camera(MapCamera(
            centerCoordinate: shiftedCenter(
                camera.centerCoordinate,
                paddingDelta: paddingDelta,
                mapPointsPerScreenPoint: settle.mapPointsPerScreenPoint,
                heading: camera.heading
            ),
            distance: camera.distance,
            heading: camera.heading,
            pitch: camera.pitch
        ))
    }

    /// Whether a padding change should keep the map where it is.
    ///
    /// Not when the app set a new position since the camera last settled: that is
    /// a deliberate framing, which should fit the new visible area. Not when the
    /// map follows the rider, whose dot stays centred, or when the rider panned
    /// it, which MapKit already leaves alone. (Only `Map` can make a position the
    /// rider moved, so that case has no test.)
    static func compensates(position: MapCameraPosition, positionAtSettle: MapCameraPosition?) -> Bool {
        guard let positionAtSettle, position == positionAtSettle else { return false }
        return !position.positionedByUser && !position.followsUserLocation
    }

    /// The camera centre that keeps the map still when the bottom padding grows by
    /// `paddingDelta` points (shrinks, when negative).
    ///
    /// MapKit centres the camera in the visible area, whose centre moves up by
    /// half the change. The new centre is the coordinate shown there now: half
    /// the change up the screen, which is the camera's heading on the ground.
    ///
    /// - Parameters:
    ///   - mapPointsPerScreenPoint: The map's scale.
    ///   - heading: The camera's heading, in degrees clockwise from north. Pitch
    ///     isn't taken into account: the panel's own framings are flat, and a map
    ///     the rider tilted is one they moved, which isn't compensated.
    static func shiftedCenter(
        _ center: CLLocationCoordinate2D,
        paddingDelta: CGFloat,
        mapPointsPerScreenPoint: Double,
        heading: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        let distance = Double(paddingDelta) / 2 * mapPointsPerScreenPoint
        let bearing = heading * .pi / 180
        let point = MKMapPoint(center)
        // Map points grow eastward in x and southward in y.
        return MKMapPoint(x: point.x + distance * sin(bearing), y: point.y - distance * cos(bearing)).coordinate
    }
}
