//
//  ProximityAlertSettingsReason.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Why a rider is being sent to Settings instead of being asked, and what to
/// tell them.
///
/// Four reasons rather than one "blocked", because the four say genuinely
/// different things: one rider has granted location and needs to widen it, one
/// has refused it, one may be unable to change it at all, and one has location
/// but no notifications. Collapsing them would put the wrong instruction in
/// front of three riders out of four — and the authorization step carries the
/// location status precisely so this distinction survives.
enum ProximityAlertSettingsReason: Equatable {
    /// Location is granted, but only While Using. Background delivery needs Always.
    case locationWhenInUse
    /// Location is off for this app, and the rider can turn it back on.
    case locationDenied
    /// Location may be restricted by a device policy the rider does not control.
    case locationRestricted
    /// Notifications are off, and the notification *is* the alert.
    case notifications
}

extension ProximityAlertSettingsReason {

    /// The copy lives on the reason rather than at the presenter, matching
    /// `ArrivalDepartureFilter.displayTitle` and `StopTripPlannerAction`'s
    /// titles: one definition per case, and adding a fifth reason makes the
    /// omission a compile error rather than a string nobody wrote.
    var alertTitle: String {
        switch self {
        case .locationWhenInUse:
            return OBALoc(
                "stop_page.proximity_alert.location_when_in_use.title",
                value: "Allow Location Always",
                comment: "Title of the alert shown when the rider has granted location only While Using, which nearby alerts cannot work with."
            )
        case .locationDenied:
            return OBALoc(
                "stop_page.proximity_alert.location_denied.title",
                value: "Location Is Off",
                comment: "Title of the alert shown when the rider tries to set a nearby alert but location is denied for the app."
            )
        case .locationRestricted:
            return OBALoc(
                "stop_page.proximity_alert.location_restricted.title",
                value: "Location Isn't Available",
                comment: "Title of the alert shown when location may be limited by a device restriction the rider does not control."
            )
        case .notifications:
            return OBALoc(
                "stop_page.proximity_alert.notifications_denied.title",
                value: "Notifications Are Off",
                comment: "Title of the alert shown when the rider tries to set a nearby alert but notifications are denied in Settings."
            )
        }
    }

    /// Distinct keys per reason rather than one key with swapped arguments: a
    /// translator sees one value per key, and a shared key would have to carry
    /// the format of whichever call site was written first.
    ///
    /// Three of the four name the app through `Bundle.main.appName` — this is a
    /// white-label framework and the alert ships in every agency's build.
    var alertMessage: String {
        switch self {
        case .locationWhenInUse:
            return String(
                format: OBALoc(
                    "stop_page.proximity_alert.location_when_in_use.message_fmt",
                    value: "%@ has location access only while it's open. Nearby alerts need it in the background too, so they can work with your phone in your pocket.",
                    comment: "Body of the alert asking the rider to widen location access from While Using to Always. %@ is the app name."
                ),
                Bundle.main.appName
            )
        case .locationDenied:
            return String(
                format: OBALoc(
                    "stop_page.proximity_alert.location_denied.message_fmt",
                    value: "To get nearby alerts, allow location for %@ in Settings.",
                    comment: "Body of the alert shown when location is denied for the app. %@ is the app name."
                ),
                Bundle.main.appName
            )
        case .locationRestricted:
            // No app name, and no promise that Settings will help: a restriction
            // may be a device policy the rider cannot lift.
            return OBALoc(
                "stop_page.proximity_alert.location_restricted.message",
                value: "Nearby alerts need location access, which may be limited by a setting on this device.",
                comment: "Body of the alert shown when location access is restricted on the device."
            )
        case .notifications:
            return String(
                format: OBALoc(
                    "stop_page.proximity_alert.notifications_denied.message_fmt",
                    value: "Nearby alerts arrive as notifications. Allow them for %@ in Settings.",
                    comment: "Body of the alert shown when notifications are denied. %@ is the app name."
                ),
                Bundle.main.appName
            )
        }
    }
}
