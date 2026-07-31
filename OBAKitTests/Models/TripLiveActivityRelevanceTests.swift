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

    /// Local refreshes must not wipe prominence — rebuilding with the default
    /// score of 0 is what kept the first-started activity in the Dynamic Island
    /// after a later Track (#1189 Problem 2).
    @Test func `Preserved score helper keeps existing prominence on refresh`() {
        let state = TripAttributes.ContentState(arrivals: [])
        let refreshed = TripLiveActivityRelevance.content(
            state: state,
            staleDate: nil,
            relevanceScore: 1_700_000_050
        )
        #expect(refreshed.relevanceScore == 1_700_000_050)
    }
}
