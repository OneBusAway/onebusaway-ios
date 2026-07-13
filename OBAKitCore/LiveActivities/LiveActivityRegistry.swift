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
/// it. On the next launch the activity is simply absent from
/// `Activity<TripAttributes>.activities`, so no lifecycle observer is ever armed for it and
/// its delete URL is orphaned. `reconcile()` is the sweep that closes that gap: any persisted
/// delete URL whose activity is no longer known to ActivityKit belongs to a dead activity, so
/// the subscription is deleted server-side.
///
/// ## Why a delete URL is only forgotten on confirmation
///
/// The persisted delete URL is the *only* handle the app has on the server-side row. If it's
/// dropped after a DELETE that failed because the network was down, the row can never be
/// deleted again — an permanent leak, worse than the bounded one reconciliation fixes. So an
/// entry is forgotten only when the server has confirmed the removal (2xx) or confirmed the
/// row is already gone (404/410). Every other failure leaves the entry in place to be retried
/// by a later `reconcile()`.
public final class LiveActivityRegistry {

    /// Field-persisted UserDefaults key: `[activityID: deleteURLString]`. Do not rename —
    /// installs in the wild have orphaned delete URLs stored under it that `reconcile()`
    /// exists to clean up.
    static let deleteURLsDefaultsKey = "liveActivityDeleteURLs"

    private let userDefaults: UserDefaults
    private let obacoServiceProvider: () -> ObacoAPIService?
    private let runningActivityIDs: () -> Set<String>

    /// - parameter userDefaults: The store for persisted delete URLs.
    /// - parameter obacoServiceProvider: Resolved per call, because `obacoService` is recreated
    ///   on region change (and is nil until a region is available).
    /// - parameter runningActivityIDs: The IDs of the Live Activities ActivityKit still knows
    ///   about. Injectable for testing; production callers should use the default.
    public init(
        userDefaults: UserDefaults,
        obacoServiceProvider: @escaping () -> ObacoAPIService?,
        runningActivityIDs: @escaping () -> Set<String> = { Set(Activity<TripAttributes>.activities.map { $0.id }) }
    ) {
        self.userDefaults = userDefaults
        self.obacoServiceProvider = obacoServiceProvider
        self.runningActivityIDs = runningActivityIDs
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

    /// Registers (or re-registers, on token rotation) `activity`'s push token with OBACloud and
    /// persists the delete URL the server hands back.
    ///
    /// - parameter confirm: Evaluated immediately before the delete URL is persisted. Callers
    ///   that may have torn the activity down while the POST was in flight return `false` here;
    ///   the registry then deletes the row the server just created rather than persisting a URL
    ///   nothing will ever act on. Both this method and `unregister(activityID:)` run on the
    ///   caller's actor (the view controllers' MainActor), so the check is race-free there.
    public func register(
        activity: Activity<TripAttributes>,
        pushToken: String,
        tripID: String?,
        serviceDate: Date?,
        vehicleID: String?,
        stopSequence: Int?,
        confirm: () -> Bool = { true }
    ) async {
        guard let obacoService = obacoServiceProvider() else { return }

        let activityID = activity.id
        let staticData = activity.attributes.staticData

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
                    try await obacoService.deleteLiveActivity(url: deleteURL)
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

    /// Deletes every persisted subscription whose Live Activity no longer exists on-device.
    ///
    /// Call this from an app-lifecycle hook (launch/foreground), not from a view controller:
    /// the orphaned registration this cleans up belongs to an activity nothing else observes
    /// anymore, so the sweep has to run regardless of which screen the user opens.
    ///
    /// Entries whose activity is still running are left alone — they're either being observed
    /// by a live lifecycle observer or will be re-armed by one.
    public func reconcile() async {
        let persisted = persistedDeleteURLs
        guard !persisted.isEmpty else { return }

        let liveActivityIDs = runningActivityIDs()

        for (activityID, urlString) in persisted where !liveActivityIDs.contains(activityID) {
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
            try await obacoService.deleteLiveActivity(url: deleteURL)
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
