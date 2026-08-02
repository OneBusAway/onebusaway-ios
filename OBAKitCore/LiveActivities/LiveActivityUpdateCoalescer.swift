//
//  LiveActivityUpdateCoalescer.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation

/// Serializes Live Activity content refreshes per activity ID (#1197).
///
/// `BookmarksViewController.updateRunningLiveActivities` used to spawn an
/// unbounded `Task.detached` per activity on every poll. Two rapid cycles could
/// apply an older `ContentState` after a newer one. This coalescer keeps only
/// the latest pending state per ID and drains them one at a time.
///
/// Relevance is always read from the **re-fetched** `Activity.content` inside
/// the detached work — not a snapshot captured on the main actor before the
/// hop — so a prominence change that landed between enqueue and apply is kept.
public actor LiveActivityUpdateCoalescer {
    public static let shared = LiveActivityUpdateCoalescer()

    private var mailbox = LiveActivityUpdateMailbox()
    private var draining: Set<String> = []

    public init() {}

    /// Enqueue a content refresh. Only the latest state per `activityID` is kept.
    public func schedule(activityID: String, state: TripAttributes.ContentState) {
        mailbox.enqueue(activityID: activityID, state: state)
        Task { await drain(activityID: activityID) }
    }

    /// Test seam: current pending count for an ID (0 or 1 after coalescing).
    public func pendingCount(for activityID: String) -> Int {
        mailbox.pending[activityID] == nil ? 0 : 1
    }

    private func drain(activityID: String) async {
        guard !draining.contains(activityID) else { return }
        draining.insert(activityID)
        defer { draining.remove(activityID) }

        while let state = mailbox.take(activityID: activityID) {
            await Self.apply(activityID: activityID, state: state)
        }
    }

    /// Re-fetches the activity by ID, preserves its current relevance score, and
    /// applies `state`. Isolated as `static` so the actor isn't held across the
    /// ActivityKit `update` await.
    nonisolated private static func apply(
        activityID: String,
        state: TripAttributes.ContentState
    ) async {
        guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }) else {
            Logger.info("Live Activity \(activityID) is no longer running; skipping coalesced update.")
            return
        }

        let existing = activity.content
        Logger.info(
            "Updating Live Activity \(activityID) stop=\(activity.attributes.staticData.stopID) route=\(activity.attributes.staticData.routeShortName) relevanceScore=\(existing.relevanceScore)"
        )

        await activity.update(
            TripLiveActivityRelevance.contentPreservingRelevance(
                state: state,
                staleDate: nil,
                existing: existing
            )
        )
    }
}

/// Pure pending-state map used by ``LiveActivityUpdateCoalescer`` so coalescing
/// rules can be unit-tested without ActivityKit (#1197).
public struct LiveActivityUpdateMailbox: Sendable {
    public private(set) var pending: [String: TripAttributes.ContentState] = [:]

    public init() {}

    public mutating func enqueue(activityID: String, state: TripAttributes.ContentState) {
        pending[activityID] = state
    }

    public mutating func take(activityID: String) -> TripAttributes.ContentState? {
        pending.removeValue(forKey: activityID)
    }
}
