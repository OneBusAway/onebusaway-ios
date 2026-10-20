//
//  ExternalNavigationHost.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

/// Where navigation that starts outside the visible UI lands when the root has
/// no classic tabs to push onto: links, notifications, widgets and Live
/// Activities, Handoff and the cold-launch stash.
///
/// The map panel's root registers itself as `Application.externalNavigationHost`.
/// The classic root doesn't: `Application.withPushableTopViewController` already
/// pushes onto its tabs.
@MainActor
protocol ExternalNavigationHost: AnyObject {
    /// Opens the stop page, over whatever the rider had open.
    ///
    /// - Parameter afterDismissal: Runs once a dismissal of a modal over the
    ///   host, started here, has finished.
    /// - Returns: true when opening waits on that dismissal, so nothing else
    ///   should be presented from the outgoing modal yet. The same contract as
    ///   `Application.withPushableTopViewController`.
    @discardableResult
    func openStop(_ stopID: StopID, afterDismissal: (@MainActor () -> Void)?) -> Bool

    /// Opens the trip page.
    ///
    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when this came from a shared trip link that named one. See #449.
    func openTrip(_ arrivalDeparture: ArrivalDeparture, destinationStopID: StopID?)

    /// The host's counterpart of one of classic's tabs.
    func show(page: ClassicApplicationRootController.Page)
}
