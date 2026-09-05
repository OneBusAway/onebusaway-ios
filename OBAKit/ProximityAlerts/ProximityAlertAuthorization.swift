//
//  ProximityAlertAuthorization.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import UserNotifications
import OBAKitCore

/// The next thing that has to happen before a proximity alert can be armed.
///
/// A proximity alert needs two permissions that the rest of the app never asks
/// for: `.authorizedAlways` location, because a geofence started under When In
/// Use only delivers while the rider is looking at the screen, and notification
/// permission, because the notification is the entire product. Each is
/// separately grantable, separately refusable, and — once refused — reachable
/// only through Settings.
///
/// Reducing all of that to a single next step keeps the decision in one place.
/// The alternative is every caller re-deriving "can I still ask, or do I send
/// them to Settings?" from a raw `CLAuthorizationStatus`, which is exactly the
/// question the status alone cannot answer.
public enum ProximityAlertAuthorizationStep: Equatable {

    /// Nothing is missing.
    case ready

    /// The app can still raise the system location prompt. Whether that prompt
    /// is the first one or the Always upgrade is iOS's business, not the
    /// caller's — both are `requestAlwaysAuthorization()`.
    case promptForLocation

    /// Location is settled and the app can still raise the notification prompt.
    case promptForNotifications

    /// Location cannot be obtained by asking, so only Settings can fix it. The
    /// status is carried because the rider's situation differs sharply between
    /// them: `.denied` is a choice they can reverse, `.restricted` may be a
    /// device policy they cannot, and `.authorizedWhenInUse` means they granted
    /// something — just not the background access this feature needs.
    case locationBlocked(CLAuthorizationStatus)

    /// Notifications cannot be obtained by asking. Carries no status: every
    /// route here wants the same thing from the rider, which is a trip to
    /// Settings, and the resolver logs the distinction for anyone reading a
    /// device log.
    case notificationsBlocked
}

extension ProximityAlertAuthorizationStep {

    /// Works out the next step from the two authorization states.
    ///
    /// Location is settled before notifications are asked about, and the order
    /// matters rather than being arbitrary: a rider who will not grant
    /// background location cannot use this feature at all, and iOS gives the
    /// notification prompt one appearance per install. Asking for notifications
    /// first would spend that one appearance on a feature already dead — and
    /// spend it in a context the rider cannot make sense of, since nothing has
    /// yet told them what the notification would be for.
    ///
    /// - Parameters:
    ///   - locationStatus: `LocationService.authorizationStatus`.
    ///   - canPromptForAlways: `LocationService.canPromptForAlwaysAuthorization`.
    ///     Distinguishes "asking will raise a prompt" from "asking will silently
    ///     do nothing", which the status alone cannot: `.authorizedWhenInUse`
    ///     looks identical either side of the one-time upgrade prompt.
    ///   - notificationStatus: the notification centre's authorization status.
    public static func resolve(
        locationStatus: CLAuthorizationStatus,
        canPromptForAlways: Bool,
        notificationStatus: UNAuthorizationStatus
    ) -> ProximityAlertAuthorizationStep {
        switch locationStatus {
        case .authorizedAlways:
            break
        case .notDetermined, .authorizedWhenInUse:
            // Both statuses can still be upgraded, but only while the one-time
            // prompt is unspent. Once it is gone they are as blocked as a denial,
            // and saying so is what stops the UI asking forever.
            guard canPromptForAlways else { return .locationBlocked(locationStatus) }
            return .promptForLocation
        case .denied, .restricted:
            return .locationBlocked(locationStatus)
        @unknown default:
            Logger.warn("Unrecognized location authorization status \(locationStatus.rawValue); treating proximity alerts as blocked.")
            return .locationBlocked(locationStatus)
        }

        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return .ready
        case .notDetermined:
            return .promptForNotifications
        case .denied:
            return .notificationsBlocked
        @unknown default:
            Logger.warn("Unrecognized notification authorization status \(notificationStatus.rawValue); treating proximity alerts as blocked.")
            return .notificationsBlocked
        }
    }
}
