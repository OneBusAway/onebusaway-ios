//
//  TripLiveActivityRelevance.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation

/// Dynamic Island / Lock Screen ordering for trip Live Activities (#1189 Problem 2).
///
/// ActivityKit shows the Live Activity with the highest `relevanceScore` in the
/// Dynamic Island. When scores are equal (or unset — default `0`), it keeps the
/// first activity that was started. Both start paths previously built
/// `ActivityContent` without a score, so tracking bookmark B after A left the
/// Island on A.
///
/// Scores are relative. A newly user-started activity gets a monotonic
/// prominence score; peers are demoted to ``demotedScore``. Local content
/// refreshes must pass the activity's existing score through
/// ``content(state:staleDate:relevanceScore:)`` — rebuilding with the default
/// of `0` undoes prominence after the next arrivals poll.
public enum TripLiveActivityRelevance {

    /// Score assigned to activities that should yield the Dynamic Island.
    public static let demotedScore: Double = 0

    /// Monotonic score for a trip the rider just chose to Track.
    public static func prominenceScore(now: Date = Date()) -> Double {
        now.timeIntervalSince1970
    }

    public static func content(
        state: TripAttributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double
    ) -> ActivityContent<TripAttributes.ContentState> {
        ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevanceScore)
    }
}

extension Activity where Attributes == TripAttributes {

    /// Lowers every *other* live trip's `relevanceScore` so `exceptActivityID`
    /// (the activity just started) keeps the Dynamic Island (#1189 Problem 2).
    ///
    /// No-ops for the excluded id and for dismissed/ended activities that
    /// ActivityKit still lists in `activities`.
    ///
    /// - Parameter prominence: The score assigned to the newly started activity.
    ///   Peers are demoted strictly below it (`demotedScore`, which must remain
    ///   lower than any prominence this app issues).
    public static func demoteLivePeers(
        exceptActivityID: String,
        relativeTo prominence: Double
    ) async {
        let demoted = TripLiveActivityRelevance.demotedScore
        assert(
            demoted < prominence,
            "demotedScore must stay below prominence so the new Track wins the Island"
        )

        for activity in activities {
            guard activity.id != exceptActivityID else { continue }
            guard LiveActivityRegistry.isLive(activity.activityState) else { continue }

            let content = TripLiveActivityRelevance.content(
                state: activity.content.state,
                staleDate: activity.content.staleDate,
                relevanceScore: demoted
            )
            await activity.update(content)
        }
    }
}
