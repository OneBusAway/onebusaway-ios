//
//  RegionStopSyncPolicyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Each boundary is checked on both sides, so `>` and `>=` can't be swapped
/// unnoticed.
@Suite(.serialized)
struct RegionStopSyncPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

    private func state(_ outcome: RegionStopSyncState.Outcome, attemptAgo: TimeInterval, successAgo: TimeInterval? = nil, etag: String? = nil, appVersion: String = "26.5") -> RegionStopSyncState {
        RegionStopSyncState(
            regionId: 1,
            outcome: outcome,
            lastAttemptAt: now.addingTimeInterval(-attemptAgo),
            lastSuccessAt: successAgo.map { now.addingTimeInterval(-$0) },
            etag: etag,
            appVersion: appVersion
        )
    }

    private func decision(_ state: RegionStopSyncState?, appVersion: String = "26.5") -> RegionStopSyncPolicy.Decision {
        RegionStopSyncPolicy.decision(for: state, now: now, appVersion: appVersion)
    }

    @Test func `A region never synced syncs now`() {
        #expect(decision(nil) == .full)
    }

    @Test func `A Java region's complete sync lasts seven days`() {
        #expect(decision(state(.complete, attemptAgo: 7 * day - 1, successAgo: 7 * day - 1)) == .skip)
        #expect(decision(state(.complete, attemptAgo: 7 * day, successAgo: 7 * day)) == .full)
    }

    @Test func `A maglev region checks its fingerprint daily and syncs fully weekly`() {
        #expect(decision(state(.complete, attemptAgo: day - 1, successAgo: day - 1, etag: "3f9a")) == .skip)
        #expect(decision(state(.complete, attemptAgo: day, successAgo: day, etag: "3f9a")) == .conditional(etag: "3f9a"))
        #expect(decision(state(.complete, attemptAgo: day, successAgo: 7 * day, etag: "3f9a")) == .full)
    }

    @Test func `A failed or partial sync is retried after an hour`() {
        for outcome in [RegionStopSyncState.Outcome.failed, .partial] {
            #expect(decision(state(outcome, attemptAgo: 3_599)) == .skip)
            #expect(decision(state(outcome, attemptAgo: 3_600)) == .full)
        }
    }

    @Test func `A server without the endpoint is left alone for seven days or until an update`() {
        for outcome in [RegionStopSyncState.Outcome.unsupported, .skippedMultiAgency] {
            #expect(decision(state(outcome, attemptAgo: 7 * day - 1)) == .skip)
            #expect(decision(state(outcome, attemptAgo: 7 * day)) == .full)
            #expect(decision(state(outcome, attemptAgo: day, appVersion: "26.4")) == .full)
        }
    }
}
