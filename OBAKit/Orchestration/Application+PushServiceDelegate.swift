//
//  Application+PushServiceDelegate.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

// MARK: - PushServiceDelegate

extension Application {
    public func pushServicePresentingController(_ pushService: PushService) -> UIViewController? {
        topViewController
    }

    public func pushService(_ pushService: PushService, received pushBody: AlarmPushBody) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Remove the fired alarm from the local store and let open stop pages
            // update their alarm index via the notification.
            self.deleteMatchingAlarm(for: pushBody)
            NotificationCenter.default.post(name: .alarmFired, object: nil)
            self.launchRouteGate.suppress()

            guard self.canNavigateFromOutside else {
                // UI not ready yet (cold launch). Navigate once the scene activates.
                self.pendingStopID = pushBody.stopID
                // A region left by an earlier stash would make the drain refuse
                // this stop as belonging to somewhere else.
                self.pendingStopRegionID = nil
                return
            }
            self.pushStopFromOutside(pushBody.stopID)
        }
    }

    public func pushService(_ pushService: PushService, receivedDeviceToken token: String) {
        pushRegistrationManager.updateDeviceToken(token)
        Task { await pushRegistrationManager.registerIfNeeded() }
    }

    public func pushService(_ pushService: PushService, receivedProximityAlertForStopID stopID: StopID, regionID: Int?) {
        // The alert's own region wins where it has one. `currentRegion` is right
        // only while it tracks the rider's location — the ordinary case, since the
        // geofence is crossed where they are — and is wrong for a manually pinned
        // region, which would send them to the pinned region's API for a stop they
        // set somewhere else. Alerts stored before they carried a region still
        // fall back to it, exactly as they always did.
        guard let regionID = regionID ?? regionsService.currentRegion?.regionIdentifier else {
            // Neither names one — the ordinary case for a tap that relaunched a
            // terminated app, since the regions list loads asynchronously. Stash
            // without one, exactly as the fired-alarm handler above does: the
            // drain navigates as soon as a root controller exists, and
            // `regionsService(_:updatedRegion:)` drains again once a region lands.
            // Returning here instead would drop the only thing the rider tapped.
            Logger.info("Proximity alert tap for stop \(stopID) arrived with no region; deferring navigation.")
            pendingStopID = stopID
            // Cleared rather than left alone: a region stashed by an earlier
            // navigation would make the drain refuse this stop as belonging to
            // somewhere else.
            pendingStopRegionID = nil
            return
        }
        // Through `queueOrOpenStop` on both branches, rather than a second copy of
        // its deferral logic here: once the region can come from the alert instead
        // of from `currentRegion`, its mismatch guard can finally disagree with
        // itself, and a tap that relaunched the app stashes a region the drain can
        // check instead of navigating against whatever loads first.
        queueOrOpenStop(AppLinksRouter.StopDestination(stopID: stopID, regionID: regionID))
    }

    /// Deletes the stored alarm whose deep-link identity matches `pushBody`, so the stop
    /// page reflects the fired state without waiting for the next full refresh.
    @MainActor
    private func deleteMatchingAlarm(for pushBody: AlarmPushBody) {
        for alarm in userDataStore.alarms {
            guard let deepLink = alarm.deepLink else { continue }
            guard deepLink.stopID == pushBody.stopID,
                  deepLink.tripID == pushBody.tripID,
                  deepLink.stopSequence == pushBody.stopSequence,
                  abs(deepLink.serviceDate.timeIntervalSince(pushBody.serviceDate)) < 60
            else { continue }
            userDataStore.delete(alarm: alarm)
            return
        }
    }
}
