//
//  LiveActivityRegistry.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ActivityKit

/// Owns the lifecycle of the app's Live Activity push subscriptions with OBACloud:
/// registering an activity's push token, unregistering it when the activity ends, and
/// reconciling the persisted registrations against the activities iOS still knows about.
///
/// ## Why reconciliation exists
///
/// A registration is only cleaned up by the app: the server keeps pushing updates to an
/// activity until its subscription is deleted (or it hits an 8-hour expiry). Observing
/// `Activity.activityStateUpdates` covers a dismissal that happens while the app is running,
/// but if the user clears the Live Activity while the app *isn't* running, nothing observes
/// it: no lifecycle observer is ever armed for it and its delete URL is orphaned.
/// `reconcile()` is the sweep that closes that gap.
///
/// ## What "dead" means (this was gotten wrong once)
///
/// A dismissed activity does **not** vanish from `Activity<TripAttributes>.activities`.
/// ActivityKit keeps it in the array and reports its state as `.dismissed` (or `.ended`) —
/// that's exactly what `.dismissed`/`.ended` exist to express, and it's the same signal the
/// view controllers' `activityStateUpdates` observers act on. A sweep that treats mere
/// *presence* in `activities` as proof of life therefore skips the dismissed activity it was
/// written to clean up, and the server keeps pushing to it forever.
///
/// So an activity is alive only if it is present in `activities` **and** its `activityState`
/// is not `.dismissed`/`.ended` (`.active`, `.stale` and `.pending` are all alive). An
/// activityID that is absent from the array entirely is dead too — the system does eventually
/// purge dismissed activities. `reconcile()` deletes the server-side subscription for every
/// persisted delete URL whose activityID is not in that live set.
///
/// ## Why a delete URL is only forgotten on confirmation
///
/// The persisted delete URL is the *only* handle the app has on the server-side row. If it's
/// dropped after a DELETE that failed because the network was down, the row can never be
/// deleted again — an permanent leak, worse than the bounded one reconciliation fixes. So an
/// entry is forgotten only when the server has confirmed the removal (2xx) or confirmed the
/// row is already gone (404/410). Every other failure leaves the entry in place to be retried
/// by a later `reconcile()`.
///
/// ## Why the DELETEs ignore task cancellation
///
/// Every DELETE this type issues is *teardown* for an activity that is already dead on-device,
/// and it is reached from tasks whose whole job is to observe that death — which means the
/// caller is frequently being torn down in the same breath. Swift's `URLSession` honors task
/// cancellation, so a DELETE started in an already-cancelled task fails instantly with
/// `URLError.cancelled` (-999) and never leaves the device; the subscription then leaks until
/// its server-side expiry and the user keeps getting pushes for a Live Activity they dismissed.
/// That shipped. See `withoutInheritingCancellation(_:)`: cancelling a cleanup request only
/// ever loses the cleanup, so these deletes deliberately outlive their caller.
public final class LiveActivityRegistry {

    /// Field-persisted UserDefaults key: `[activityID: deleteURLString]`. Do not rename —
    /// installs in the wild have orphaned delete URLs stored under it that `reconcile()`
    /// exists to clean up.
    static let deleteURLsDefaultsKey = "liveActivityDeleteURLs"

    private let userDefaults: UserDefaults
    private let obacoServiceProvider: () -> ObacoAPIService?
    private let liveActivityIDs: () -> Set<String>

    /// Whether an activity in `Activity<TripAttributes>.activities` is still alive.
    ///
    /// `.dismissed` and `.ended` activities remain in the array — being listed there is not
    /// evidence of life. Written as a pair of `!=` checks rather than an allow-list of live
    /// states so that a state case added by a future OS defaults to "alive": a false negative
    /// here would delete the subscription of an activity the user is still looking at, which is
    /// worse than a bounded leak.
    public static func isLive(_ state: ActivityState) -> Bool {
        state != .dismissed && state != .ended
    }

    /// - parameter userDefaults: The store for persisted delete URLs.
    /// - parameter obacoServiceProvider: Resolved per call, because `obacoService` is recreated
    ///   on region change (and is nil until a region is available).
    /// - parameter liveActivityIDs: The IDs of the Live Activities that are both known to
    ///   ActivityKit *and* in a live state — see `isLive(_:)` and the type's documentation; an
    ///   ID missing from this set is treated as dead and its subscription is swept. Injectable
    ///   for testing; production callers should use the default.
    public init(
        userDefaults: UserDefaults,
        obacoServiceProvider: @escaping () -> ObacoAPIService?,
        liveActivityIDs: @escaping () -> Set<String> = {
            Set(Activity<TripAttributes>.activities.lazy.filter { isLive($0.activityState) }.map { $0.id })
        }
    ) {
        self.userDefaults = userDefaults
        self.obacoServiceProvider = obacoServiceProvider
        self.liveActivityIDs = liveActivityIDs
    }

    // MARK: - Persistence

    /// `[activityID: deleteURLString]`
    var persistedDeleteURLs: [String: String] {
        userDefaults.dictionary(forKey: Self.deleteURLsDefaultsKey) as? [String: String] ?? [:]
    }

    func deleteURL(forActivityID activityID: String) -> URL? {
        persistedDeleteURLs[activityID].flatMap(URL.init(string:))
    }

    private func store(deleteURL: URL, activityID: String) {
        var urls = persistedDeleteURLs
        urls[activityID] = deleteURL.absoluteString
        userDefaults.set(urls, forKey: Self.deleteURLsDefaultsKey)
    }

    /// Drops the persisted delete URL for `activityID`. Only call once the server has confirmed
    /// the subscription is gone — see the type's documentation.
    private func forget(activityID: String) {
        var urls = persistedDeleteURLs
        guard urls.removeValue(forKey: activityID) != nil else { return }
        userDefaults.set(urls, forKey: Self.deleteURLsDefaultsKey)
    }

    // MARK: - Register

    /// Registers (or re-registers, on token rotation) an activity's push token with OBACloud and
    /// persists the delete URL the server hands back.
    ///
    /// Takes the activity's `id` and `attributes.staticData` rather than the `Activity` itself:
    /// `Activity` can't be constructed outside a Live-Activity-capable process, so a method that
    /// demanded one would drag the whole registration path — including the orphan cleanup below,
    /// which is exactly the sort of code that rots unobserved — out of reach of the test suite.
    ///
    /// - parameter confirm: Evaluated immediately before the delete URL is persisted. Callers
    ///   that may have torn the activity down while the POST was in flight return `false` here;
    ///   the registry then deletes the row the server just created rather than persisting a URL
    ///   nothing will ever act on. Both this method and `unregister(activityID:)` run on the
    ///   caller's actor (the view controllers' MainActor), so the check is race-free there.
    public func register(
        activityID: String,
        staticData: TripAttributes.StaticData,
        pushToken: String,
        tripID: String?,
        serviceDate: Date?,
        vehicleID: String?,
        stopSequence: Int?,
        confirm: () -> Bool = { true }
    ) async {
        guard let obacoService = obacoServiceProvider() else { return }

        do {
            let deleteURL = try await obacoService.postLiveActivity(
                activityID: activityID,
                pushToken: pushToken,
                stopID: staticData.stopID,
                routeShortName: staticData.routeShortName,
                tripHeadsign: staticData.routeHeadsign,
                tripID: tripID,
                serviceDate: serviceDate,
                vehicleID: vehicleID,
                stopSequence: stopSequence
            )

            guard confirm() else {
                do {
                    // `confirm()` returns false precisely because the caller's task was torn down
                    // mid-POST — so this cleanup runs inside an already-cancelled task, and must
                    // opt out of that cancellation or it would never be sent. See the type docs.
                    try await withoutInheritingCancellation {
                        _ = try await obacoService.deleteLiveActivity(url: deleteURL)
                    }
                    Logger.info("Discarded Live Activity registration for \(activityID): activity was unregistered mid-request")
                } catch {
                    // Nothing to persist and nothing to retry against: the activity is already
                    // gone locally, so the server row expires on its own.
                    Logger.error("Failed to clean up orphaned Live Activity registration for \(activityID): \(error)")
                }
                return
            }

            store(deleteURL: deleteURL, activityID: activityID)
            Logger.info("Registered Live Activity push token for activity \(activityID)")
        } catch {
            Logger.error("Failed to register Live Activity push token for \(activityID): \(error)")
        }
    }

    // MARK: - Unregister

    /// Deletes the server-side subscription for `activityID`, which has ended or been dismissed
    /// on-device. A no-op when nothing is persisted for it.
    public func unregister(activityID: String) async {
        guard let deleteURL = deleteURL(forActivityID: activityID) else { return }
        await deleteSubscription(activityID: activityID, deleteURL: deleteURL)
    }

    // MARK: - Reconcile

    /// Deletes every persisted subscription whose Live Activity is dead on-device — dismissed,
    /// ended, or gone from `Activity<TripAttributes>.activities` altogether. See the type's
    /// documentation: a dismissed activity is still *listed* by ActivityKit, so presence in that
    /// array is not what makes an activity alive.
    ///
    /// Call this from an app-lifecycle hook (launch/foreground), not from a view controller:
    /// the orphaned registration this cleans up belongs to an activity nothing else observes
    /// anymore, so the sweep has to run regardless of which screen the user opens.
    ///
    /// Entries whose activity is still alive are left alone — they're either being observed by
    /// a live lifecycle observer or will be re-armed by one.
    public func reconcile() async {
        let persisted = persistedDeleteURLs
        guard !persisted.isEmpty else {
            Logger.info("Live Activity reconcile: no persisted subscriptions; nothing to sweep")
            return
        }

        let liveIDs = liveActivityIDs()
        let dead = persisted.filter { !liveIDs.contains($0.key) }

        // Logged unconditionally, including the do-nothing case: a sweep that wrongly decides
        // every subscription is alive is precisely the bug that shipped, and it was silent.
        Logger.info("Live Activity reconcile: \(persisted.count) persisted subscription(s), \(liveIDs.count) live on-device, sweeping \(dead.count) dead")

        for (activityID, urlString) in dead {
            guard let deleteURL = URL(string: urlString) else {
                // Unusable handle: there's no request we could ever make with it, so keeping it
                // would just fail this check on every launch forever.
                Logger.error("Discarding unparseable Live Activity delete URL for \(activityID): \(urlString)")
                forget(activityID: activityID)
                continue
            }

            Logger.info("Reconciling orphaned Live Activity subscription for \(activityID)")
            await deleteSubscription(activityID: activityID, deleteURL: deleteURL)
        }
    }

    // MARK: - Deletion

    /// DELETEs `deleteURL`, and forgets the persisted entry only if the server confirms the
    /// subscription is gone. A transient failure (offline, timeout, 5xx) leaves the entry
    /// persisted so a later `reconcile()` retries it.
    private func deleteSubscription(activityID: String, deleteURL: URL) async {
        guard let obacoService = obacoServiceProvider() else {
            // No region, so no service to talk to. Keep the entry and retry on a later pass.
            return
        }

        do {
            try await withoutInheritingCancellation {
                _ = try await obacoService.deleteLiveActivity(url: deleteURL)
            }
            forget(activityID: activityID)
            Logger.info("Unregistered Live Activity \(activityID)")
        } catch {
            guard Self.serverConfirmedSubscriptionIsGone(error) else {
                Logger.error("Failed to unregister Live Activity \(activityID), will retry: \(error)")
                return
            }

            forget(activityID: activityID)
            Logger.info("Live Activity subscription \(activityID) was already gone server-side; dropped its delete URL")
        }
    }

    /// Runs `work` in a task that does not inherit the caller's cancellation.
    ///
    /// Every caller of this is a *cleanup* request: a DELETE for a Live Activity that is already
    /// dead on-device. Such a request is reached from a task that is being torn down at that very
    /// moment (a lifecycle observer that just saw `.dismissed`, a push-token task cancelled
    /// mid-registration), and `URLSession` refuses to send a request from a cancelled task —
    /// `URLError.cancelled`, -999, before a single byte goes out. Honoring cancellation here can
    /// therefore only ever *lose* the cleanup and leak the subscription; there is no caller for
    /// whom "abandon the DELETE" is the desired outcome. `Task.detached` is what buys the
    /// immunity: unlike `Task {}`, it has no parent to inherit a cancelled state from.
    private func withoutInheritingCancellation(_ work: @escaping @Sendable () async throws -> Void) async throws {
        try await Task.detached { try await work() }.value
    }

    /// Whether `error` means the server *told us* the subscription no longer exists, as opposed
    /// to us failing to reach the server at all.
    ///
    /// `APIService.data(for:)` maps a 404 to `APIError.requestNotFound` and every other non-2xx
    /// status to `APIError.requestFailure`, so 410 Gone has to be picked out by status code.
    /// Anything else — `URLError`, `APIError.networkFailure`, a 5xx `requestFailure` — is
    /// treated as transient and the delete URL is retained.
    static func serverConfirmedSubscriptionIsGone(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return false }

        switch apiError {
        case .requestNotFound:
            return true
        case .requestFailure(let response):
            return response.statusCode == 410
        default:
            return false
        }
    }
}
