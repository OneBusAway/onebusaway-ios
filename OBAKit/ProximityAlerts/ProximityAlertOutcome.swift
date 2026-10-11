//
//  ProximityAlertOutcome.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// The single next thing the Stop page should do about a proximity alert.
///
/// An enum rather than the struct-of-`Bool`s shape `StopPageActionRowState`
/// uses. That shape fits continuous UI state, where several things are true at
/// once; this produces exactly one of N discrete actions, and an enum return
/// makes covering all of them a compile-time property instead of a review
/// question.
enum ProximityAlertUIAction: Equatable {
    /// An alert is already set on this stop: take it down.
    case cancel(ProximityAlert)
    /// Nothing is missing. Ask the manager to arm one.
    case arm
    /// An alert armed. Show the rider the confirmation.
    case confirmActivated
    /// Raise the system Always-location prompt.
    case requestLocation
    /// Raise the system notification prompt.
    case requestNotifications
    /// Asking would raise nothing; only Settings can fix it.
    case showSettings(ProximityAlertSettingsReason)
    /// iOS already monitors every region it allows.
    case showLimit(Int)
    /// The page's idea of this stop's alert is stale. Re-read it, say nothing.
    case refresh
    /// Authorization moved between resolving the step and arming. Resolve again.
    case resolveAgain
}

/// Turns the manager's two reported outcomes into the one action the UI takes.
///
/// Split out of `StopPageActionPresenter` so the decisions can be tested at all.
/// The presenter's flow begins by reading the device's real location and
/// notification authorization, which on a test runner is a fresh, undetermined
/// install — so most of these states are unreachable there, and driving it past
/// the first one would raise system prompts. Pure: no dependencies, no
/// presentation, no state. The strings, alerts and prompts belong to the caller.
enum ProximityAlertOutcome {

    /// What to do about a tap on the menu item.
    ///
    /// - Parameters:
    ///   - step: what `ProximityAlertManager.authorizationStep()` reported.
    ///   - existing: the unexpired alert already set on this stop, if any.
    ///     Checked before `step`: a rider taking an alert *down* needs no
    ///     permission, and reading the step first would send someone whose
    ///     authorization has since been revoked to Settings to cancel something.
    static func action(
        forStep step: ProximityAlertAuthorizationStep,
        existing: ProximityAlert?
    ) -> ProximityAlertUIAction {
        if let existing {
            return .cancel(existing)
        }

        switch step {
        case .ready:
            return .arm
        case .promptForLocation:
            return .requestLocation
        case .promptForNotifications:
            return .requestNotifications
        case .locationBlocked(let status):
            return .showSettings(settingsReason(forLocationStatus: status))
        case .notificationsBlocked:
            return .showSettings(.notifications)
        }
    }

    /// What to do about the manager's answer to an arming attempt.
    static func action(forResult result: ProximityAlertActivationResult) -> ProximityAlertUIAction {
        switch result {
        case .activated:
            return .confirmActivated
        case .activatedWithClampedRadius:
            // Still a success, and still worth confirming: the alert will fire,
            // just closer in than asked. The manager logs both radii, and the
            // rider never chose one to be told about — the radius is fixed.
            return .confirmActivated
        case .alreadyActive:
            // The menu offered "Alert Me" against state that had already moved on.
            // Re-reading it flips the item without claiming the tap did anything.
            return .refresh
        case .needsLocationAuthorization, .needsNotificationAuthorization:
            // Authorization changed between resolving the step and arming — the
            // rider answered a prompt, or revoked something from Settings, in the
            // window between the two. The step resolver can say what to do about
            // it; a raw status cannot.
            return .resolveAgain
        case .regionLimitReached(let limit):
            return .showLimit(limit)
        }
    }

    /// Which Settings copy a `.locationBlocked` status calls for.
    ///
    /// `.notDetermined` reaches here in one narrow case: the one-time prompt is
    /// spent but the status never moved, which is what a missing
    /// `NSLocationAlwaysAndWhenInUseUsageDescription` — or an "Allow Once"
    /// answer — leaves behind. The rider has granted nothing, so the same copy
    /// as `.denied` is the accurate one.
    private static func settingsReason(forLocationStatus status: CLAuthorizationStatus) -> ProximityAlertSettingsReason {
        switch status {
        case .authorizedWhenInUse:
            return .locationWhenInUse
        case .denied, .notDetermined:
            return .locationDenied
        case .restricted:
            return .locationRestricted
        case .authorizedAlways:
            // Unreachable through `ProximityAlertAuthorizationStep.resolve`, which
            // never calls Always blocked. Answer with the copy that promises the
            // rider nothing rather than one that would be a lie if it ever happens.
            Logger.warn("Proximity alerts are blocked while location authorization reads authorizedAlways; falling back to the restricted guidance.")
            return .locationRestricted
        @unknown default:
            Logger.warn("Unrecognized location authorization status \(status.rawValue) blocked a proximity alert; falling back to the restricted guidance.")
            return .locationRestricted
        }
    }
}
