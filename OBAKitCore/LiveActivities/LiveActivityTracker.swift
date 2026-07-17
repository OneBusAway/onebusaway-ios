//
//  LiveActivityTracker.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ActivityKit

/// Owns the ActivityKit observers that feed `LiveActivityRegistry`: one task per activity
/// forwarding its push token, and one watching for its dismissal.
///
/// ## Why this is app-scoped and not per-view-controller
///
/// These observers outlive the screen that started the activity. A Live Activity begun from a
/// stop page keeps running after the user taps back, and the only thing that deletes its
/// server-side subscription when they finally swipe it away is its lifecycle observer. Parking
/// that observer on the view controller ties its life to the screen: popping `StopPageViewController`
/// deallocates it, cancels the observer, and the eventual dismissal is then seen by nobody, so
/// the server keeps pushing to an activity the user has cleared. (`LiveActivityRegistry.reconcile()`
/// sweeps that up, but only on the next foreground — the leak lasts as long as the app stays open.)
///
/// A single tracker hanging off `CoreApplication` lives as long as the process, so there is no
/// `deinit` teardown here at all: an observer is retired when its activity ends, not when a screen
/// closes. It also means an activity has exactly one set of observers no matter which screen
/// started it, so two view controllers can't independently arm — and independently tear down —
/// the same activity.
///
/// Being a single `@MainActor` owner is also what makes the `confirm` check in
/// `LiveActivityRegistry.register` race-free: the read of `lifecycleTasks` and the write in
/// `unregister` are on the same actor, and now there is only one dictionary to be the truth.
@MainActor
public final class LiveActivityTracker {

    nonisolated(unsafe) private let registry: LiveActivityRegistry

    /// One token-forwarding task per activity id.
    private var tokenTasks: [String: Task<Void, Never>] = [:]

    /// One lifecycle-observation task per activity id.
    private var lifecycleTasks: [String: Task<Void, Never>] = [:]

    public nonisolated init(registry: LiveActivityRegistry) {
        self.registry = registry
    }

    /// The trip context that OBACloud needs in order to push updates to an activity. All fields
    /// are optional because a bookmark with no loaded arrivals has none of them; the server
    /// falls back to matching on the activity's stop and route in that case.
    public struct TripMetadata {
        public let tripID: String?
        public let serviceDate: Date?
        public let vehicleID: String?
        public let stopSequence: Int?

        public init(tripID: String?, serviceDate: Date?, vehicleID: String?, stopSequence: Int?) {
            self.tripID = tripID
            self.serviceDate = serviceDate
            self.vehicleID = vehicleID
            self.stopSequence = stopSequence
        }

        public init(_ arrivalDeparture: ArrivalDeparture?) {
            self.init(
                tripID: arrivalDeparture?.tripID,
                serviceDate: arrivalDeparture?.serviceDate,
                vehicleID: arrivalDeparture?.vehicleID,
                stopSequence: arrivalDeparture?.stopSequence
            )
        }
    }

    /// Whether anything is watching `activityID` for its death. False means no one will delete
    /// its server-side subscription when it ends, so at minimum `observeLifecycle(of:)` is owed.
    public func isTracking(activityID: String) -> Bool {
        tokenTasks[activityID] != nil || lifecycleTasks[activityID] != nil
    }

    /// Whether `activityID`'s push token is being forwarded to OBACloud — i.e. it has a *full*
    /// registration and not just the lifecycle observer that `observeLifecycle(of:)` arms alone.
    ///
    /// Distinct from `isTracking(activityID:)` because an activity can legitimately be upgraded
    /// from lifecycle-only to fully tracked: a relaunch sweep that can't match an activity to a
    /// bookmark arms only the lifecycle observer, and if that bookmark later reappears the sweep
    /// must still be able to arm the token task. Gating that on `isTracking` would see the
    /// lifecycle observer, conclude the activity was handled, and leave it without push updates
    /// forever.
    public func isForwardingPushToken(activityID: String) -> Bool {
        tokenTasks[activityID] != nil
    }

    /// Forwards `activity`'s push token to OBACloud as it rotates, and unregisters the activity
    /// when it ends. Call this for an activity you just started, or for one found still running
    /// after a relaunch whose trip context you can still resolve.
    public func track(activity: Activity<TripAttributes>, metadata: TripMetadata) {
        let activityID = activity.id

        tokenTasks[activityID]?.cancel()
        tokenTasks[activityID] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await self?.register(activity: activity, pushToken: token, metadata: metadata)
            }
        }

        observeLifecycle(of: activity)
    }

    /// Observes `activity`'s dismiss/end state so its server-side subscription is deleted, without
    /// registering a push token.
    ///
    /// This is the relaunch case for an activity whose bookmark can no longer be matched: there's
    /// no trip context to register with, but a delete URL persisted in a previous session still
    /// needs to be cleaned up once the activity ends.
    public func observeLifecycle(of activity: Activity<TripAttributes>) {
        let activityID = activity.id

        lifecycleTasks[activityID]?.cancel()
        lifecycleTasks[activityID] = Task { [weak self] in
            for await state in activity.activityStateUpdates where !LiveActivityRegistry.isLive(state) {
                await self?.unregister(activityID: activityID)
                break
            }
        }
    }

    private func register(activity: Activity<TripAttributes>, pushToken: String, metadata: TripMetadata) async {
        await registry.register(
            activityID: activity.id,
            staticData: activity.attributes.staticData,
            pushToken: pushToken,
            tripID: metadata.tripID,
            serviceDate: metadata.serviceDate,
            vehicleID: metadata.vehicleID,
            stopSequence: metadata.stopSequence,
            confirm: { [weak self] in
                // `unregister` is only cooperatively cancelled, so it can finish tearing down this
                // activity's tasks while the POST is still in flight. If that happened, the
                // lifecycle task that would eventually DELETE this registration is already gone, so
                // persisting the delete URL now would orphan it forever. The registry evaluates
                // this immediately before the write (both this method and `unregister` are on the
                // MainActor, so the check is race-free) and cleans up the row the server just
                // created for us when it returns false.
                guard let self else { return false }
                return self.lifecycleTasks[activity.id] != nil && !Task.isCancelled
            }
        )
    }

    /// Tears down the observers for `activityID` and deletes its server-side push subscription.
    ///
    /// The ordering below is load-bearing, and the tempting tidy-up — cancelling both tasks
    /// together, up front — is a bug. This method's usual caller is the lifecycle task itself
    /// (`observeLifecycle(of:)`), so cancelling that task here cancels *the task we are currently
    /// running inside*. `URLSession` honors task cancellation, so the DELETE that follows would
    /// fail instantly with `URLError.cancelled` (-999) without a byte leaving the device —
    /// silently, since unregistration has no UI. That shipped: every dismissal leaked its
    /// subscription and the server kept pushing to a Live Activity the user had cleared.
    ///
    /// So: drop the lifecycle task from the dictionary (which is what `confirm` in `register`
    /// reads, and what stops a second unregister), but cancel it only *after* the network call.
    /// When we're running inside it, it's about to `break` out of its loop anyway; when called
    /// from anywhere else, it still gets torn down properly.
    ///
    /// The token task is a different task and is safe to cancel up front.
    ///
    /// `LiveActivityRegistry` independently refuses to let its DELETEs inherit cancellation, so
    /// this is belt-and-braces — but the belt is here, where the reasoning is visible.
    private func unregister(activityID: String) async {
        tokenTasks.removeValue(forKey: activityID)?.cancel()
        let lifecycleTask = lifecycleTasks.removeValue(forKey: activityID)

        await registry.unregister(activityID: activityID)

        lifecycleTask?.cancel()
    }
}
