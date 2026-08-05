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
/// the latest pending state per ID and applies states for that ID serially.
public actor LiveActivityUpdateCoalescer {
    public typealias Apply = @Sendable (String, TripAttributes.ContentState) async -> Void

    public static let shared = LiveActivityUpdateCoalescer()

    private var mailbox = LiveActivityUpdateMailbox()
    private var draining: Set<String> = []
    private let applyState: Apply

    public init() {
        applyState = Self.applyToActivity
    }

    public init(apply: @escaping Apply) {
        applyState = apply
    }

    /// Enqueue a content refresh. Only the latest state per `activityID` is kept.
    public func schedule(activityID: String, state: TripAttributes.ContentState) {
        mailbox.enqueue(activityID: activityID, state: state)
        Task { await drain(activityID: activityID) }
    }

    private func drain(activityID: String) async {
        guard !draining.contains(activityID) else { return }
        draining.insert(activityID)
        defer { draining.remove(activityID) }

        while let state = mailbox.take(activityID: activityID) {
            await applyState(activityID, state)
        }
    }

    /// Re-fetches the activity by ID, preserves its current relevance score, and
    /// applies `state`.
    nonisolated private static func applyToActivity(
        activityID: String,
        state: TripAttributes.ContentState
    ) async {
        guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }) else {
            Logger.info("Live Activity \(activityID) is no longer running; skipping coalesced update.")
            return
        }

        let existing = activity.content
        // `staleDate` stays nil here on purpose: unlike the score-only
        // promote/demote touches (which must carry the push-set marker
        // through), this installs fresh local content. Carrying a possibly
        // past stale date forward could mark it stale on arrival; the next
        // push re-arms it.
        await activity.update(
            TripLiveActivityRelevance.contentPreservingRelevance(
                state: state,
                staleDate: nil,
                existing: existing
            )
        )
        Logger.info(
            "Updated Live Activity \(activityID) stop=\(activity.attributes.staticData.stopID) route=\(activity.attributes.staticData.routeShortName) relevanceScore=\(existing.relevanceScore)"
        )
    }
}

/// Pending content state keyed by Live Activity ID.
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
