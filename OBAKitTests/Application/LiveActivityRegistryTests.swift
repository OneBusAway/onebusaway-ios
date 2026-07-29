//
//  LiveActivityRegistryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import ActivityKit
@testable import OBAKit
@testable import OBAKitCore

/// Covers `LiveActivityRegistry`'s reconciliation sweep and unregistration.
///
/// Two invariants are load-bearing here:
///
/// 1. **Dead means dismissed/ended/absent, not merely absent.** ActivityKit keeps a dismissed
///    activity in `Activity.activities` with an `activityState` of `.dismissed`. A sweep that
///    equates "listed" with "alive" skips the very activity it exists to clean up — that bug
///    shipped, and the server pushed to a dismissed activity indefinitely. Because `Activity`
///    can't be constructed in a test, the registry takes the *live* activity IDs as an
///    injectable seam; these tests build that set out of `(id, ActivityState)` pairs run
///    through the registry's own `isLive(_:)` predicate, so a regression in the predicate fails
///    here rather than on a device.
/// 2. **A delete URL may only be forgotten once the server confirms it.** It's the only handle
///    the app has on the server-side subscription, so dropping it after a failed DELETE leaks
///    the subscription permanently.
@Suite(.serialized)
final class LiveActivityRegistryTests: OBATestCase {

    private let deadActivityID = "dead-activity"
    private let liveActivityID = "live-activity"

    private var deadDeleteURL: URL {
        URL(string: "https://alerts.example.com/api/v2/regions/1/live_activities/\(deadActivityID)")!
    }

    private var liveDeleteURL: URL {
        URL(string: "https://alerts.example.com/api/v2/regions/1/live_activities/\(liveActivityID)")!
    }

    private var dataLoader: MockDataLoader {
        // swiftlint:disable:next force_cast
        obacoService.dataLoader as! MockDataLoader
    }

    /// Builds a registry backed by the test's UserDefaults suite and mocked Obaco service.
    /// - parameter liveActivityIDs: Stands in for the IDs of the activities in
    ///   `Activity<TripAttributes>.activities` that are in a live state.
    private func buildRegistry(liveActivityIDs: Set<String>) -> LiveActivityRegistry {
        let service: ObacoAPIService = obacoService
        return LiveActivityRegistry(
            userDefaults: userDefaults,
            obacoServiceProvider: { service },
            liveActivityIDs: { liveActivityIDs }
        )
    }

    /// Builds a registry whose live set is derived from a stand-in for
    /// `Activity<TripAttributes>.activities`: every activity ActivityKit still *lists*, paired
    /// with the state it reports. Filtering happens through the production `isLive(_:)`
    /// predicate, so "present but `.dismissed`" is a case these tests can actually express.
    private func buildRegistry(activityKitReports activities: [(id: String, state: ActivityState)]) -> LiveActivityRegistry {
        let live = Set(activities.filter { LiveActivityRegistry.isLive($0.state) }.map(\.id))
        return buildRegistry(liveActivityIDs: live)
    }

    private func persistDeleteURLs(_ urls: [String: String]) {
        userDefaults.set(urls, forKey: LiveActivityRegistry.deleteURLsDefaultsKey)
    }

    private var persistedDeleteURLs: [String: String] {
        userDefaults.dictionary(forKey: LiveActivityRegistry.deleteURLsDefaultsKey) as? [String: String] ?? [:]
    }

    /// Mocks every DELETE to the live activities endpoint with the given status and records the
    /// URLs it saw.
    @discardableResult
    private func mockDeleteResponse(statusCode: Int) -> DeleteRecorder {
        let recorder = DeleteRecorder()
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            guard request.httpMethod == "DELETE", let url = request.url else { return false }
            recorder.record(url)
            return true
        }
        return recorder
    }

    /// Mocks every DELETE with a transport-level failure — no response at all, as if the device
    /// were offline.
    @discardableResult
    private func mockDeleteFailure(_ error: Error) -> DeleteRecorder {
        let recorder = DeleteRecorder()
        let response = MockDataResponse(data: nil, urlResponse: nil, error: error) { request in
            guard request.httpMethod == "DELETE", let url = request.url else { return false }
            recorder.record(url)
            return true
        }
        dataLoader.mock(response: response)
        return recorder
    }

    /// Thread-safe collector for the DELETEs a registry issued.
    ///
    /// `nonisolated` is load-bearing. The matcher closure that calls `record(_:)`
    /// is invoked by `MockDataLoader` on whichever task issued the request, and
    /// `reconcile()` deliberately sends its DELETEs from a detached task so they
    /// outlive the caller's cancellation. Left on the target's main-actor default
    /// isolation, that call tripped the runtime's isolation assertion and killed
    /// the test process — which is exactly what happened when this target moved
    /// to the Swift 6 language mode. `MockDataLoaderMatcher` is `@Sendable` now,
    /// so the same mistake would be caught at build time rather than at runtime.
    /// The lock, not the actor, is what makes this safe, so `@unchecked Sendable`
    /// states the promise the lock already keeps.
    private nonisolated final class DeleteRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _urls = [URL]()

        func record(_ url: URL) {
            lock.withLock { _urls.append(url) }
        }

        var urls: [URL] {
            lock.withLock { _urls }
        }
    }

    // MARK: - What counts as alive

    /// The predicate the whole sweep turns on. `.dismissed`/`.ended` are the two states the view
    /// controllers' `activityStateUpdates` observers treat as death; everything else is alive.
    @Test func `Only dismissed and ended activities are considered dead`() {
        #expect(!LiveActivityRegistry.isLive(.dismissed), "A dismissed activity is dead, even though ActivityKit still lists it.")
        #expect(!LiveActivityRegistry.isLive(.ended), "An ended activity is dead, even though ActivityKit still lists it.")

        #expect(LiveActivityRegistry.isLive(.active))
        #expect(LiveActivityRegistry.isLive(.stale))

        // `.pending` postdates our deployment target, hence the gate. It's also the reason
        // `isLive(_:)` is written as "not dead" rather than as an allow-list of live states: a
        // state case the app was never compiled against must not be mistaken for death.
        if #available(iOS 26.0, *) {
            #expect(LiveActivityRegistry.isLive(.pending))
        }
    }

    // MARK: - reconcile()

    /// The regression that shipped. The user dismissed the Live Activity, but ActivityKit *still
    /// lists it* in `Activity.activities` — with a state of `.dismissed`. The original sweep
    /// checked only for presence in that array, concluded the activity was alive, skipped it, and
    /// the server went on pushing to a dead activity forever. Presence is not life.
    @Test func `Reconcile sweeps activity still listed by activity kit but dismissed`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: [(deadActivityID, .dismissed)]).reconcile()

        #expect(recorder.urls == [deadDeleteURL], "Expected reconcile() to DELETE the subscription for a dismissed activity that ActivityKit still lists.")
        #expect(persistedDeleteURLs.isEmpty, "Expected a confirmed DELETE to drop the persisted delete URL.")
    }

    /// Same regression, other dead state: an `.ended` activity also lingers in `activities`.
    @Test func `Reconcile sweeps activity still listed by activity kit but ended`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: [(deadActivityID, .ended)]).reconcile()

        #expect(recorder.urls == [deadDeleteURL], "Expected reconcile() to DELETE the subscription for an ended activity that ActivityKit still lists.")
        #expect(persistedDeleteURLs.isEmpty)
    }

    /// The user cleared a Live Activity while the app wasn't running and the system has since
    /// purged it: nothing ever observed the dismissal, so its delete URL was left behind.
    @Test func `Reconcile deletes subscription for activity that no longer exists`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: []).reconcile()

        #expect(recorder.urls == [deadDeleteURL], "Expected reconcile() to DELETE the subscription for an activity that no longer exists.")
        #expect(persistedDeleteURLs.isEmpty, "Expected a confirmed DELETE to drop the persisted delete URL.")
    }

    /// An active activity still has (or will get) a lifecycle observer that unregisters it when
    /// it ends. Reconciliation must not touch it — sweeping it would kill the updates for a Live
    /// Activity the user is looking at right now.
    @Test func `Reconcile leaves active activity alone`() async {
        persistDeleteURLs([liveActivityID: liveDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: [(liveActivityID, .active)]).reconcile()

        #expect(recorder.urls.isEmpty, "Expected reconcile() to make no requests for an active activity.")
        #expect(persistedDeleteURLs == [liveActivityID: liveDeleteURL.absoluteString], "Expected an active activity's delete URL to be retained.")
    }

    /// `.stale` means "on screen, showing old data" — the exact situation a push update is meant
    /// to fix. Sweeping it would guarantee it stays stale.
    @Test func `Reconcile leaves stale activity alone`() async {
        persistDeleteURLs([liveActivityID: liveDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: [(liveActivityID, .stale)]).reconcile()

        #expect(recorder.urls.isEmpty, "Expected reconcile() to make no requests for a stale (but still live) activity.")
        #expect(persistedDeleteURLs == [liveActivityID: liveDeleteURL.absoluteString])
    }

    /// Both activities are listed by ActivityKit; only their states tell them apart.
    @Test func `Reconcile only sweeps the dismissed activity when both are listed`() async {
        persistDeleteURLs([
            deadActivityID: deadDeleteURL.absoluteString,
            liveActivityID: liveDeleteURL.absoluteString
        ])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(activityKitReports: [
            (deadActivityID, .dismissed),
            (liveActivityID, .active)
        ]).reconcile()

        #expect(recorder.urls == [deadDeleteURL])
        #expect(persistedDeleteURLs == [liveActivityID: liveDeleteURL.absoluteString])
    }

    /// The critical failure mode: if a flaky network let us forget the delete URL, the server-side
    /// subscription could never be deleted again. A transient failure must leave the entry in
    /// place so a later launch retries it.
    @Test func `Reconcile retains delete URL when the device is offline`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteFailure(URLError(.notConnectedToInternet))

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(recorder.urls == [deadDeleteURL])
        #expect(persistedDeleteURLs == [deadActivityID: deadDeleteURL.absoluteString], "Expected a transient DELETE failure to retain the persisted delete URL for a later retry.")
    }

    @Test func `Reconcile retains delete URL on server error`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 500)

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(persistedDeleteURLs == [deadActivityID: deadDeleteURL.absoluteString], "Expected a 500 to be treated as transient and retain the persisted delete URL.")
    }

    /// A retry that finds the row already deleted has nothing left to do, so the entry can go.
    @Test func `Reconcile forgets delete URL when server reports 404`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 404)

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(persistedDeleteURLs.isEmpty, "Expected a 404 (the subscription is already gone) to drop the persisted delete URL.")
    }

    @Test func `Reconcile forgets delete URL when server reports 410`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteResponse(statusCode: 410)

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(persistedDeleteURLs.isEmpty, "Expected a 410 Gone to drop the persisted delete URL.")
    }

    /// A malformed entry can never produce a request, so retaining it would just fail this check
    /// forever.
    @Test func `Reconcile discards unparseable delete URL`() async {
        persistDeleteURLs([deadActivityID: ""])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(recorder.urls.isEmpty)
        #expect(persistedDeleteURLs.isEmpty)
    }

    @Test func `Reconcile makes no requests when nothing is persisted`() async {
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(liveActivityIDs: []).reconcile()

        #expect(recorder.urls.isEmpty)
    }

    // MARK: - unregister()

    @Test func `Unregister deletes subscription and forgets its URL`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(liveActivityIDs: []).unregister(activityID: deadActivityID)

        #expect(recorder.urls == [deadDeleteURL])
        #expect(persistedDeleteURLs.isEmpty)
    }

    @Test func `Unregister retains delete URL when the device is offline`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        mockDeleteFailure(URLError(.timedOut))

        await buildRegistry(liveActivityIDs: []).unregister(activityID: deadActivityID)

        #expect(persistedDeleteURLs == [deadActivityID: deadDeleteURL.absoluteString], "Expected a transient DELETE failure to retain the persisted delete URL so reconcile() can retry it.")
    }

    @Test func `Unregister is a no op for an unknown activity`() async {
        let recorder = mockDeleteResponse(statusCode: 204)

        await buildRegistry(liveActivityIDs: []).unregister(activityID: "never-registered")

        #expect(recorder.urls.isEmpty)
    }

    // MARK: - Cancellation

    /// The bug a device had to find. `unregister` is reached from the view controllers' lifecycle
    /// observer — a `Task` that awaits `activityStateUpdates` — and that observer used to cancel
    /// *itself* before awaiting this call. `URLSession` refuses to send a request from a cancelled
    /// task, so the DELETE died as `URLError.cancelled` (-999) before a byte left the device, on
    /// every dismissal, in every scenario. The subscription leaked and the server kept pushing.
    ///
    /// So the property under test is not "unregister sends a DELETE" (the tests above already
    /// pass with the bug present) but "unregister sends a DELETE *even from a cancelled task*".
    /// `MockDataLoader` models `URLSession`'s cancellation check, so this fails without the fix.
    @Test func `Unregister issues its delete even when the calling task is cancelled`() async {
        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])
        let recorder = mockDeleteResponse(statusCode: 204)

        let registry = buildRegistry(liveActivityIDs: [])
        let activityID = deadActivityID
        let expectedURL = deadDeleteURL

        // Stands in for the lifecycle observer at the moment it cancels itself: by the time
        // `unregister` runs, the enclosing task is already cancelled. Spinning until the
        // cancellation is visible keeps this deterministic rather than a race with `cancel()`.
        let observer = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            await registry.unregister(activityID: activityID)
        }
        observer.cancel()
        await observer.value

        #expect(recorder.urls == [expectedURL], "The unregister DELETE must reach the network even though the task that triggered it was cancelled — cancelling teardown work only ever leaks the subscription.")
        #expect(persistedDeleteURLs.isEmpty, "Expected the confirmed DELETE to drop the persisted delete URL.")
    }

    /// The same defect, one layer over: the registration POST wins its race with a dismissal, so
    /// `confirm()` returns false and the registry must DELETE the row the server just created.
    /// That cleanup runs inside the push-token task — which is cancelled, because being cancelled
    /// is *why* `confirm()` returned false. Cancellation-honoring cleanup here orphans a row that
    /// nothing else will ever delete: the app never persisted its delete URL, so `reconcile()`
    /// can't find it either.
    @Test func `Register cleans up the orphaned row even when its token task was cancelled mid registration`() async {
        let registry = buildRegistry(liveActivityIDs: [])
        let deleteRecorder = mockDeleteResponse(statusCode: 204)
        let activityID = deadActivityID
        let expectedURL = deadDeleteURL

        // Lets the mocked POST cancel the very task that issued it.
        let tokenTask = SendableBox<Task<Void, Never>?>(nil)

        let registrationBody = Data(#"{"url":"\#(deadDeleteURL.absoluteString)"}"#.utf8)
        dataLoader.mock(data: registrationBody, statusCode: 200) { request in
            guard request.httpMethod == "POST" else { return false }
            // The production race, made deterministic: the user dismisses the Live Activity while
            // its push token registration is still in flight, so the token task is cancelled after
            // the server has already created the row.
            tokenTask.value?.cancel()
            return true
        }

        // The token task can't be handed to the box until it exists, so gate its body until it has
        // been: otherwise the POST could fire before there's anything for the matcher to cancel.
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }

            await registry.register(
                activityID: activityID,
                staticData: TripAttributes.StaticData(routeShortName: "49", routeHeadsign: "Downtown", stopID: "1_75403"),
                pushToken: "deadbeef",
                tripID: nil,
                serviceDate: nil,
                vehicleID: nil,
                stopSequence: nil,
                // Mirrors the view controllers' confirm: a cancelled token task means the activity
                // was torn down mid-request, so the delete URL must not be persisted.
                confirm: { !Task.isCancelled }
            )
        }
        tokenTask.value = task
        gate.continuation.yield(())
        gate.continuation.finish()
        await task.value

        #expect(deleteRecorder.urls == [expectedURL], "The orphan-cleanup DELETE must reach the network even though the token task issuing it was cancelled.")
        #expect(persistedDeleteURLs.isEmpty, "An unconfirmed registration must not leave a persisted delete URL behind.")
    }

    /// Guards the seam the two tests above lean on. They can only fail against the buggy ordering
    /// if `MockDataLoader` refuses to serve a request from a cancelled task, the way `URLSession`
    /// does. If someone "simplifies" that check away, those tests would go on passing while the
    /// device kept failing — so assert the mock's fidelity directly.
    @Test func `Mock data loader refuses to serve requests from a cancelled task like URL session`() async {
        let recorder = mockDeleteResponse(statusCode: 204)
        let service: ObacoAPIService = obacoService
        let url = deadDeleteURL

        let task = Task { () -> Error? in
            while !Task.isCancelled {
                await Task.yield()
            }
            do {
                _ = try await service.deleteLiveActivity(url: url)
                return nil
            } catch {
                return error
            }
        }
        task.cancel()
        let error = await task.value

        #expect((error as? URLError)?.code == .cancelled, "Expected the mock to fail a request from a cancelled task with URLError.cancelled (-999), exactly as URLSession does.")
        #expect(recorder.urls.isEmpty, "A cancelled request is one the server never saw; the mock must not record it.")
    }

    // MARK: - Persistence contract

    /// The key and value shape are a field-persisted contract: delete URLs written by shipped
    /// builds must still be found (and cleaned up) by this code.
    @Test func `Registry reads the legacy user defaults key and shape`() {
        #expect(LiveActivityRegistry.deleteURLsDefaultsKey == "liveActivityDeleteURLs")

        persistDeleteURLs([deadActivityID: deadDeleteURL.absoluteString])

        let registry = buildRegistry(liveActivityIDs: [])
        #expect(registry.deleteURL(forActivityID: deadActivityID) == deadDeleteURL)
    }
}
