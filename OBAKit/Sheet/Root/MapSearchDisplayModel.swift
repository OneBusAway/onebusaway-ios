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

    /// The sheet route this display belongs to, and the thing that decides how long
    /// it stays on the map.
    ///
    /// Lifetime is keyed to the route stack rather than to the owning sheet view's
    /// `onDisappear`, which is what this originally used. `onDisappear` reads like a
    /// dismissal signal but isn't one: the floating-sheet system rebuilds a sheet's
    /// content view for reasons that have nothing to do with the user leaving —
    /// stacked layers being re-presented, the base sheet's content swapping
    /// underneath — and each rebuild fired a `clear()` that wiped a route off the map
    /// seconds after it was drawn, while its sheet sat there still visible.
    ///
    /// The route stack is the actual record of what's on screen, so ask it.
    @Published private(set) var owner: AppSheetRoute?

    /// While a route is drawn, the ambient stop pins are hidden and stop loading is
    /// skipped so the route's own stops are the only ones on the map — the SwiftUI
    /// counterpart of the UIKit path's `removeAllAnnotations()` plus
    /// `searchResponseOverridesStopLoading()`.
    var suppressesAmbientStops: Bool {
        if case .route = display { return true }
        return false
    }

    func show(mapItem: MKMapItem, animated: Bool, owner: AppSheetRoute) {
        self.owner = owner
        display = .mapItem(mapItem)
        cameraTarget = .coordinate(mapItem.placemark.coordinate, animated: animated)
    }

    func show(stop: Stop, owner: AppSheetRoute) {
        self.owner = owner
        display = .stop(stop)
        cameraTarget = .coordinate(stop.coordinate, animated: true)
    }

    func show(stopsForRoute: StopsForRoute, owner: AppSheetRoute) {
        self.owner = owner
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

    /// Moves the camera without changing what's displayed — used when the user picks
    /// a stop out of a route's list and the polyline should stay on screen.
    func focus(coordinate: CLLocationCoordinate2D) {
        cameraTarget = .coordinate(coordinate, animated: true)
    }

    /// Applies-and-forgets the pending camera move. Called by the view once it has
    /// moved the camera.
    func consumeCameraTarget() {
        cameraTarget = nil
    }

    /// Drops the display once the route that owns it is no longer anywhere in the
    /// sheet stack. Called on every change to that stack.
    ///
    /// Deriving the decision from the stack, rather than acting on a dismissal event,
    /// makes this self-correcting: a route that is popped and immediately re-pushed
    /// (what a search does while it resolves a result) is still present when this
    /// runs, so nothing is wiped in the gap.
    ///
    /// - Parameter routes: Every route currently on screen — both sheet layers.
    func clearIfOwnerAbsent(from routes: [AppSheetRoute]) {
        guard let owner, !routes.contains(owner) else { return }
        clear()
    }

    func clear() {
        owner = nil
        display = .none
        cameraTarget = nil
    }
}
