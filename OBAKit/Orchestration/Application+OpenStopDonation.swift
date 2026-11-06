//
//  Application+OpenStopDonation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

extension Application {
    /// Tells Siri the rider opened `stop`, when a stop page is about to publish
    /// `activity` in place of `previous`. The activity itself no longer asks for
    /// predictions (#1556).
    ///
    /// Pages republish on every appearance, and the legacy page on every arrivals
    /// refresh. Those keep the identifier, so each page instance counts only its
    /// first activity for a stop as an open. A new page for the same stop counts
    /// again.
    ///
    /// A stop that `OpenStopIntent` opened isn't donated, because the system already
    /// records the intents it runs. That covers the one open: a request that never
    /// reaches a page costs that stop one donation at most.
    func donateOpenStop(_ stop: Stop, publishing activity: NSUserActivity?, replacing previous: NSUserActivity?) {
        guard let activity,
              activity.persistentIdentifier != previous?.persistentIdentifier,
              let region = regionsService.currentRegion else { return }

        if stopOpenedByIntent == AppLinksRouter.StopDestination(stopID: stop.id, regionID: region.regionIdentifier) {
            stopOpenedByIntent = nil
            return
        }

        intentDonor.donateOpenStop(StopEntityMapping.entity(for: stop, regionID: region.regionIdentifier))
    }
}
