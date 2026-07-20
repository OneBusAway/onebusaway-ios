//
//  LiveActivityLookup.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit

extension TripAttributes.StaticData {

    /// Whether two `StaticData` describe the same tracked trip: the same route,
    /// with the same headsign, arriving at the same stop.
    ///
    /// This is the single definition of Live Activity identity — the start
    /// paths' duplicate guards and the bookmark-reconciliation match all
    /// delegate to it, so "the same tracked trip" can't quietly come to mean
    /// two different things.
    ///
    /// `routeColorHex` and `regionID` are excluded on purpose. Both are
    /// presentation/routing metadata rather than identity, and the colour in
    /// particular is read from the first arrival payload — it is nil until
    /// arrivals load. Folding it into identity would let a duplicate through in
    /// exactly the case this guards against: a second tap before data arrives.
    public func tracksSameTrip(as other: TripAttributes.StaticData) -> Bool {
        stopID == other.stopID
            && routeShortName == other.routeShortName
            && routeHeadsign == other.routeHeadsign
    }
}

extension Activity where Attributes == TripAttributes {

    /// The Live Activity already running for `staticData`'s stop and route, if any.
    ///
    /// Every `Activity.request` mints a brand-new activity with a fresh id, and
    /// nothing downstream dedupes by content: `LiveActivityTracker` and
    /// `LiveActivityRegistry` are both keyed on `activity.id`. So a start path
    /// that doesn't consult this leaves the user with two Lock Screen cards —
    /// and two OBACloud push registrations — for a single trip.
    ///
    /// Only *live* activities count. ActivityKit keeps dismissed and ended
    /// activities in `activities`, so presence in that array is not evidence the
    /// user is still looking at one; a guard written against mere presence would
    /// refuse to start an activity the user had already dismissed. See
    /// `LiveActivityRegistry.isLive(_:)`.
    public static func running(matching staticData: TripAttributes.StaticData) -> Activity<TripAttributes>? {
        activities.first { activity in
            LiveActivityRegistry.isLive(activity.activityState)
                && activity.attributes.staticData.tracksSameTrip(as: staticData)
        }
    }
}
