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
/// `ActivityContent` construction that the bookmark/stop start paths share —
/// the same seam pattern as `TripAttributesIdentityTests` for Problem 1.
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

        // Contrast: the default ActivityContent score is 0. If the call site
        // ever drops back to `.init(state:staleDate:)`, this is what Island gets.
        let wiped = ActivityContent(state: refreshedState, staleDate: nil)
        #expect(wiped.relevanceScore == 0)
        #expect(wiped.relevanceScore != existing.relevanceScore)
    }
}
