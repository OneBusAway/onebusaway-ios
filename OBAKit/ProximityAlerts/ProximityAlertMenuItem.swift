//
//  ProximityAlertMenuItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The Stop page's proximity-alert menu item, as the two presentations that
/// draw it both need it.
///
/// The title lives here for the reason `StopTripPlannerAction`'s does: the
/// pushed page builds a `UIAction` and the sheet builds a SwiftUI `Label`, from
/// different frameworks in different files, and a rider who sees one word in the
/// navigation bar and another in the toolbar is looking at a bug. One
/// definition, two readers. The glyph is `Icons.proximityAlert(isActive:)`, for
/// the same reason.
enum ProximityAlertMenuItem {

    /// The item's title, which names what the tap will do rather than what is
    /// currently true — the same shape the departure rows' alarm affordance
    /// uses, and what stops one row reading as a status and the next as a verb.
    static func title(isActive: Bool) -> String {
        isActive ? cancelTitle : setTitle
    }

    // MARK: - Accessibility Semantics

    /// Stable accessibility label describing the nearby alert action.
    static var accessibilityLabel: String {
        OBALoc(
            "stop_page.proximity_alert.a11y_label",
            value: "Nearby alert",
            comment: "VoiceOver accessibility label for the proximity alert action."
        )
    }

    /// Accessibility label for the proximity alert action given its active state.
    static func accessibilityLabel(isActive: Bool) -> String {
        title(isActive: isActive)
    }

    /// Spoken value describing whether a proximity alert is currently armed.
    static func accessibilityValue(isActive: Bool) -> String {
        isActive
            ? OBALoc("stop_page.proximity_alert.a11y_value_active", value: "active", comment: "VoiceOver value when nearby alert is active.")
            : OBALoc("stop_page.proximity_alert.a11y_value_inactive", value: "inactive", comment: "VoiceOver value when nearby alert is inactive.")
    }

    /// VoiceOver hint describing the outcome of activating the proximity alert action.
    static func accessibilityHint(isActive: Bool) -> String {
        isActive
            ? OBALoc("stop_page.proximity_alert.a11y_hint_cancel", value: "Cancels the nearby alert for this stop.", comment: "VoiceOver hint when nearby alert is active.")
            : OBALoc("stop_page.proximity_alert.a11y_hint_set", value: "Alerts you when approaching this stop.", comment: "VoiceOver hint when nearby alert is inactive.")
    }

    private static var setTitle: String {
        OBALoc(
            "stop_page.proximity_alert.menu.set",
            value: "Alert Me When Nearby",
            comment: "Stop Location menu action that sets a notification for when the rider approaches this stop."
        )
    }

    private static var cancelTitle: String {
        OBALoc(
            "stop_page.proximity_alert.menu.cancel",
            value: "Cancel Nearby Alert",
            comment: "Stop Location menu action that takes down the approach notification already set on this stop."
        )
    }
}
