//
//  MapSearchDisplayModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import SwiftUI
import OBAKitCore

/// What the SwiftUI map should draw for the current search result, and where the
/// camera should point.
///
/// The UIKit equivalent lives inside `MapRegionManager.searchResponse.didSet`, which
/// mutates an `MKMapView` directly. The SwiftUI panel has no such view to mutate, so
/// the same decisions are expressed as state here and rendered by `MapPanelRootView`.
@MainActor
final class MapSearchDisplayModel: ObservableObject {

    /// Everything the map builder needs for a displayed route, resolved once so it
    /// isn't re-derived on every body evaluation. `body` re-runs on unrelated state
    /// changes — including the continuous sheet-height updates while the sheet is
    /// dragged — so decoding polylines there would be costly.
    struct RouteDisplay {
        let polylines: [MKPolyline]
        let stops: [Stop]
        let color: Color
        let mapRect: MKMapRect
    }

    enum Display {
        case none
        case mapItem(MKMapItem)
        case route(RouteDisplay)
        case stop(Stop)
    }

    /// Where the camera should move next. One-shot: the view applies it and calls
    /// `consumeCameraTarget()`, so a later unrelated body evaluation can't re-move
    /// the map out from under the user.
    enum CameraTarget: Equatable {
        case coordinate(CLLocationCoordinate2D, animated: Bool)
        case rect(MKMapRect)

        static func == (lhs: CameraTarget, rhs: CameraTarget) -> Bool {
            switch (lhs, rhs) {
            case (.coordinate(let l, let la), .coordinate(let r, let ra)):
                return l.latitude == r.latitude && l.longitude == r.longitude && la == ra
            case (.rect(let l), .rect(let r)):
                return l.origin.x == r.origin.x && l.origin.y == r.origin.y
                    && l.size.width == r.size.width && l.size.height == r.size.height
            default:
                return false
            }
        }
    }

    @Published private(set) var display: Display = .none
    @Published private(set) var cameraTarget: CameraTarget?

    /// While a route is drawn, the ambient stop pins are hidden and stop loading is
    /// skipped so the route's own stops are the only ones on the map — the SwiftUI
    /// counterpart of the UIKit path's `removeAllAnnotations()` plus
    /// `searchResponseOverridesStopLoading()`.
    var suppressesAmbientStops: Bool {
        if case .route = display { return true }
        return false
    }

    func show(mapItem: MKMapItem, animated: Bool) {
        display = .mapItem(mapItem)
        cameraTarget = .coordinate(mapItem.placemark.coordinate, animated: animated)
    }

    func show(stop: Stop) {
        display = .stop(stop)
        cameraTarget = .coordinate(stop.coordinate, animated: true)
    }

    func show(stopsForRoute: StopsForRoute) {
        let color = stopsForRoute.route.map { Color(uiColor: $0.color ?? ThemeColors.shared.brand) }
            ?? Color(uiColor: ThemeColors.shared.brand)

        display = .route(RouteDisplay(
            polylines: stopsForRoute.polylines,
            stops: stopsForRoute.stops ?? [],
            color: color,
            mapRect: stopsForRoute.mapRect
        ))
        // Expand the bounding rect so the route isn't flush against the screen
        // edges, with extra room at the bottom for the sheet — the SwiftUI
        // equivalent of the UIKit path's `mapRectThatFits(edgePadding:)`.
        cameraTarget = .rect(stopsForRoute.mapRect.insetBy(
            dx: -stopsForRoute.mapRect.size.width * 0.15,
            dy: -stopsForRoute.mapRect.size.height * 0.30
        ))
    }

    /// Applies-and-forgets the pending camera move. Called by the view once it has
    /// moved the camera.
    func consumeCameraTarget() {
        cameraTarget = nil
    }

    func clear() {
        display = .none
        cameraTarget = nil
    }
}
