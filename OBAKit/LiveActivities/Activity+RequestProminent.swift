//
//  Activity+RequestProminent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation
import OBAKitCore

extension Activity where Attributes == TripAttributes {

    /// Starts a trip Live Activity that takes over the Dynamic Island, demoting
    /// any peers that are still live (#1189 Problem 2).
    ///
    /// One prominence score has to reach two places that must agree: the new
    /// activity's `ActivityContent`, and the demotion the peers are measured
    /// against. Assembling that pairing by hand is what let the trip page ship
    /// with neither half — a bare `.init(state:staleDate:)` scores `0`, so the
    /// Island stayed on whichever trip was already running (#1375).
    ///
    /// The pairing can't be caught by a test: `Activity.request` doesn't run in
    /// this target, and no test in `OBAKitTests` reaches one. Owning both halves
    /// in a single place is the substitute for coverage that can't exist, and is
    /// what keeps the next start path from repeating the omission.
    ///
    /// Callers keep their own tracking and UI feedback — those are the parts
    /// that legitimately differ between the bookmark, stop, and trip paths.
    static func requestProminent(
        attributes: TripAttributes,
        state: TripAttributes.ContentState,
        staleDate: Date? = nil
    ) throws -> Activity<TripAttributes> {
        let prominence = TripLiveActivityRelevance.prominenceScore()

        let activity = try Activity.request(
            attributes: attributes,
            content: TripLiveActivityRelevance.content(
                state: state,
                staleDate: staleDate,
                relevanceScore: prominence
            ),
            pushType: .token
        )

        // Hop with the id rather than the activity: `Activity` is not `Sendable`,
        // and the demotion only ever needed the identity to skip.
        let activityID = activity.id
        Task {
            await Activity<TripAttributes>.demoteLivePeers(
                exceptActivityID: activityID,
                relativeTo: prominence
            )
        }

        return activity
    }
}
