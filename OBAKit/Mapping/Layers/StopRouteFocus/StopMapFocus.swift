//
//  StopMapFocus.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import Foundation
import OBAKitCore

/// The single channel between the stop sheet and the map layer.
///
/// Route chips write focus; vehicle markers write focus; the layer reads it. One
/// value, so the two input surfaces can never disagree about what is focused.
///
/// Always non-nil, even for presentations that never attach to a map — an inert
/// instance is simpler than an Optional, and `@ObservedObject` cannot wrap an
/// Optional anyway.
@MainActor
final class StopMapFocus: ObservableObject {

    /// Routes the map is actually drawing. Chips look themselves up here for
    /// decoration; a chip with no match renders plain and is inert.
    @Published private(set) var routes: [StopRouteFocusModel.DrawnRoute] = []

    @Published private(set) var focusedRouteID: RouteID?

    /// The layer's one write path.
    func apply(routes: [StopRouteFocusModel.DrawnRoute]) {
        self.routes = routes

        // Don't let focus dangle on a route that has left the arrival set, or
        // that has lost its last live vehicle — there would be nothing on the
        // map to point at, and the chip that could clear it may be gone too.
        if let focusedRouteID,
           !routes.contains(where: { $0.routeID == focusedRouteID && $0.hasLiveVehicle }) {
            self.focusedRouteID = nil
        }
    }

    /// Focus is a momentary map emphasis, not a list filter. A route with no live
    /// vehicle is deliberately a no-op rather than an error: there is nothing to
    /// point at, and an error would be noise.
    func toggleFocus(routeID: RouteID) {
        guard isFocusable(routeID: routeID) else { return }
        focusedRouteID = (focusedRouteID == routeID) ? nil : routeID
    }

    /// Focus a route outright, never clearing it.
    ///
    /// Marker taps need this rather than `toggleFocus`: two buses can be running
    /// the same route, and tapping the second one is a request to look at that
    /// bus — not to unfocus the route the rider is already following.
    func focus(routeID: RouteID) {
        guard isFocusable(routeID: routeID) else { return }
        focusedRouteID = routeID
    }

    func clearFocus() {
        focusedRouteID = nil
    }

    /// Whether a chip for `routeID` should render as interactive.
    func isFocusable(routeID: RouteID) -> Bool {
        routes.contains { $0.routeID == routeID && $0.hasLiveVehicle }
    }

    /// Decoration for a chip, or nil when the map isn't drawing this route.
    func drawnRoute(for routeID: RouteID) -> StopRouteFocusModel.DrawnRoute? {
        routes.first { $0.routeID == routeID }
    }
}
