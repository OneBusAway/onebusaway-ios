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
/// first activity that was started. The start paths originally built
/// `ActivityContent` without a score, so tracking bookmark B after A left the
/// Island on A.
///
/// Scores are relative. A newly user-started (or re-tracked) activity gets a
/// monotonic prominence score; peers are demoted to ``demotedScore``. Local
/// content refreshes must go through ``contentPreservingRelevance`` — rebuilding
/// with the default of `0` undoes prominence after the next arrivals poll.
///
/// Starting an activity is not done from here: `Activity.request` is unavailable
/// to app extensions and this target is `APPLICATION_EXTENSION_API_ONLY`. The
/// three start paths go through `Activity.requestProminent` in OBAKit, which
/// pairs the score below with the matching ``demoteLivePeers`` call.
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

    /// The stale marker a promotion should carry.
    ///
    /// A score-only promotion keeps whatever the push set: the content is
    /// unchanged, so clearing it would leave a re-Tracked card unmarked as stale
    /// until the next push arrived. Installing fresh content is the opposite —
    /// a date set for the *previous* content could mark new arrivals stale the
    /// moment they land. ``LiveActivityUpdateCoalescer`` clears it for that same
    /// reason, and the next push re-arms it.
    public static func promotionStaleDate(
        installing state: TripAttributes.ContentState?,
        existing: Date?
    ) -> Date? {
        state == nil ? existing : nil
    }

    /// Rebuilds content for a local arrivals refresh while keeping the activity's
    /// current Dynamic Island ranking. Passing anything other than
    /// `existing.relevanceScore` here is how the Island used to snap back to the
    /// first-started trip after every poll.
    public static func contentPreservingRelevance(
        state: TripAttributes.ContentState,
        staleDate: Date? = nil,
        existing: ActivityContent<TripAttributes.ContentState>
    ) -> ActivityContent<TripAttributes.ContentState> {
        content(state: state, staleDate: staleDate, relevanceScore: existing.relevanceScore)
    }
}

extension Activity where Attributes == TripAttributes {

    /// Bumps the live activity identified by `activityID` to a fresh prominence
    /// score and demotes every other live peer so the Dynamic Island follows a
    /// re-Track of an already-running trip (#1189 Problem 2 review).
    ///
    /// Takes an id (not `Activity`) so callers can hop into a `Task` without
    /// sending a non-`Sendable` ActivityKit value across isolation.
    /// - Parameter state: Fresh content to install alongside the score bump, when
    ///   the caller has it. A re-Track happens with current arrivals already
    ///   loaded, and the card would otherwise keep whatever the last push left
    ///   (#1390). Omit it for a score-only promotion.
    public static func promoteToDynamicIsland(
        activityID: String,
        state: TripAttributes.ContentState? = nil
    ) async {
        guard let activity = activities.first(where: { $0.id == activityID }),
              LiveActivityRegistry.isLive(activity.activityState) else {
            return
        }
        let prominence = TripLiveActivityRelevance.prominenceScore()
        await activity.update(
            TripLiveActivityRelevance.content(
                state: state ?? activity.content.state,
                staleDate: TripLiveActivityRelevance.promotionStaleDate(
                    installing: state,
                    existing: activity.content.staleDate
                ),
                relevanceScore: prominence
            )
        )
        await demoteLivePeers(exceptActivityID: activityID, relativeTo: prominence)
    }

    /// Lowers every *other* live trip's `relevanceScore` so `exceptActivityID`
    /// (the activity just started or promoted) keeps the Dynamic Island
    /// (#1189 Problem 2).
    ///
    /// No-ops for the excluded id and for dismissed/ended activities that
    /// ActivityKit still lists in `activities`.
    ///
    /// - Parameter prominence: The score assigned to the newly started / promoted
    ///   activity. Peers are demoted strictly below it (`demotedScore`, which must
    ///   remain lower than any prominence this app issues).
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
