//
//  LaunchRouteGate.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Decides whether the map opens on the route a white-label app names in
/// `OBAKitConfig.LaunchRouteID`.
///
/// The route is offered at most once per launch, and only while nothing else has
/// decided what the rider should see: a deep link, a donated shortcut, a tapped
/// notification, or a restored tab other than the map all suppress it.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/617
struct LaunchRouteGate {
    /// The configured route, or `nil` when the key is absent or blank.
    let routeID: RouteID?

    private(set) var isClaimed = false
    private(set) var isSuppressed = false

    init(configValue: String?) {
        let trimmed = configValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        routeID = trimmed.isEmpty ? nil : trimmed
    }

    /// Something else now owns the screen; the launch route must not appear this launch.
    mutating func suppress() {
        isSuppressed = true
    }

    /// Returns the route ID the first time it is asked once a region is available, and
    /// `nil` on every other call. Without a region it returns `nil` without consuming
    /// the claim, because the route can only be looked up against a region's server.
    mutating func claim(hasRegion: Bool, hasPendingNavigation: Bool) -> RouteID? {
        guard let routeID, !isClaimed, !isSuppressed, hasRegion else { return nil }

        // A stop stashed for later navigation will open over the map as soon as it
        // drains; drawing a route underneath it would only flash past.
        if hasPendingNavigation {
            isSuppressed = true
            return nil
        }

        isClaimed = true
        return routeID
    }

    /// Whether a route that finished loading may still be drawn. The fetch is
    /// asynchronous, so a deep link or a rider's own search can land first.
    func mayDisplay(polylineCount: Int, isMapShowingOtherContent: Bool) -> Bool {
        isClaimed && !isSuppressed && polylineCount > 0 && !isMapShowingOtherContent
    }
}
