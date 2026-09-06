//
//  TripLiveActivityRelevanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation
import Testing
@testable import OBAKitCore

/// Pins the Dynamic Island prominence policy for #1189 Problem 2.
///
/// ActivityKit itself isn't injectable, so these tests lock the score math and
/// `ActivityContent` construction that the three start paths share through
/// `Activity.requestProminent` — the same seam pattern as
/// `TripAttributesIdentityTests` for Problem 1.
@MainActor
@Suite(.serialized)
final class TripLiveActivityRelevanceTests {

    @Test func `Prominence score is strictly above demoted score`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let prominence = TripLiveActivityRelevance.prominenceScore(now: now)
        #expect(prominence > TripLiveActivityRelevance.demotedScore)
        #expect(prominence == now.timeIntervalSince1970)
    }

    @Test func `Later track outranks earlier track`() {
        let earlier = TripLiveActivityRelevance.prominenceScore(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = TripLiveActivityRelevance.prominenceScore(
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )
        #expect(later > earlier)
    }

    /// The trip page's pre-#1375 construction didn't merely score low — a bare
    /// `ActivityContent` scores `0`, which is exactly ``demotedScore``. A trip
    /// tracked from that page was born indistinguishable from a peer that had
    /// been deliberately demoted, so it could never take the Island from a
    /// bookmark or stop Track scoring `prominenceScore()`.
    @Test func `A bare content state is born at the demoted score`() {
        let state = TripAttributes.ContentState(arrivals: [])
        let bare = ActivityContent(state: state, staleDate: nil)

        #expect(bare.relevanceScore == TripLiveActivityRelevance.demotedScore)

        let started = TripLiveActivityRelevance.content(
            state: state,
            staleDate: nil,
            relevanceScore: TripLiveActivityRelevance.prominenceScore()
        )
        #expect(started.relevanceScore > bare.relevanceScore)
    }

    @Test func `Content carries the supplied relevance score`() {
        let state = TripAttributes.ContentState(arrivals: [])
        let content = TripLiveActivityRelevance.content(
            state: state,
            staleDate: nil,
            relevanceScore: 42
        )
        #expect(content.state == state)
        #expect(content.relevanceScore == 42)
        #expect(content.staleDate == nil)
    }

    /// Pins the score-only touch pattern `promoteToDynamicIsland` and
    /// `demoteLivePeers` share: rebuilding content to change the score must
    /// carry the existing `staleDate` through — clearing it would strip the
    /// push-set stale marker from a card whose content didn't change
    /// (#1243 review follow-up).
    @Test func `Content carries the supplied stale date through a score change`() {
        let state = TripAttributes.ContentState(arrivals: [])
        let staleDate = Date(timeIntervalSince1970: 1_700_000_200)

        let promoted = TripLiveActivityRelevance.content(
            state: state,
            staleDate: staleDate,
            relevanceScore: 7
        )

        #expect(promoted.staleDate == staleDate)
        #expect(promoted.relevanceScore == 7)
    }

    /// The two halves of a promotion's stale handling (#1390). A score-only
    /// re-Track leaves the content alone, so dropping the push-set marker would
    /// leave a stale card looking live until the next push. Installing fresh
    /// arrivals inverts that: the existing date was set for content that no
    /// longer exists, and carrying it forward could mark the new arrivals stale
    /// the moment they land.
    @Test func `A promotion keeps the stale marker only when content is unchanged`() {
        let pushSet = Date(timeIntervalSince1970: 1_700_000_200)

        #expect(
            TripLiveActivityRelevance.promotionStaleDate(installing: nil, existing: pushSet) == pushSet,
            "A score-only promotion must carry the push-set marker through"
        )

        let fresh = TripAttributes.ContentState(arrivals: [])
        #expect(
            TripLiveActivityRelevance.promotionStaleDate(installing: fresh, existing: pushSet) == nil,
            "Fresh content must not inherit the previous content's stale date"
        )

        // Nothing to carry is still nothing, either way.
        #expect(TripLiveActivityRelevance.promotionStaleDate(installing: nil, existing: nil) == nil)
        #expect(TripLiveActivityRelevance.promotionStaleDate(installing: fresh, existing: nil) == nil)
    }

    /// Pins the refresh path used by `updateRunningLiveActivities`: the new
    /// content state may change, but the score must come from the *existing*
    /// content — not a literal, and not the ActivityContent default of `0`.
    /// Building with a bare `.init(state:staleDate:)` would score `0` and fail
    /// the second expectation, which is the regression this guards.
    @Test func `Content preserving relevance keeps existing score across state refresh`() {
        let previousState = TripAttributes.ContentState(arrivals: [])
        let existing = TripLiveActivityRelevance.content(
            state: previousState,
            staleDate: nil,
            relevanceScore: 1_700_000_050
        )
        let refreshedState = TripAttributes.ContentState(arrivals: [
            .init(
                departureTime: 1_700_000_100,
                scheduleStatus: .onTime,
                scheduleDeviation: 0,
                isArrival: false
            )
        ])

        let refreshed = TripLiveActivityRelevance.contentPreservingRelevance(
            state: refreshedState,
            staleDate: nil,
            existing: existing
        )

        #expect(refreshed.state == refreshedState)
        #expect(refreshed.relevanceScore == existing.relevanceScore)
        #expect(refreshed.relevanceScore == 1_700_000_050)

        // Contrast: the default ActivityContent score is 0. This is what the
        // Island got from the trip page, which built content with a bare
        // `.init(state:staleDate:)` until #1375 routed all three start paths
        // through `Activity.requestProminent`.
        let wiped = ActivityContent(state: refreshedState, staleDate: nil)
        #expect(wiped.relevanceScore == 0)
        #expect(wiped.relevanceScore != existing.relevanceScore)
    }
}
