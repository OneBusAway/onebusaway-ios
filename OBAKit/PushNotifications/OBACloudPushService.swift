//
//  OBACloudPushService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import UserNotifications
import OBAKitCore

/// A `PushServiceProvider` implementation that uses Apple Push Notification service (APNs) directly,
/// without any third-party push notification SDK.
///
/// `OBACloudPushService` manages the full APNs lifecycle: requesting notification authorization from the user,
/// registering for remote notifications, converting the raw device token to a hex string, and forwarding
/// received notifications to the app via ``notificationReceivedHandler``.
///
/// This class is intended to be used as the `serviceProvider` for ``PushService``. The `AppDelegate` must
/// forward its `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` and
/// `application(_:didFailToRegisterForRemoteNotificationsWithError:)` callbacks to this object.
@objc(OBACloudPushService)
public class OBACloudPushService: NSObject, PushServiceProvider {
    /// Called when a push notification is received. Set by ``PushService`` during initialization.
    public var notificationReceivedHandler: PushServiceNotificationReceivedHandler!

    /// Called when an error occurs during push registration or authorization. Set by ``PushService`` during initialization.
    public var errorHandler: PushServiceErrorHandler!

    /// The hex-encoded APNs device token, or `nil` if the device has not yet registered.
    private var deviceToken: String?

    /// Callbacks waiting for the device token to become available.
    private var pendingCallbacks: [PushManagerUserIDCallback] = []

    // MARK: - PushServiceProvider

    /// Configures the notification center delegate.
    ///
    /// Call this from `application(_:didFinishLaunchingWithOptions:)`.
    /// - Parameter launchOptions: The launch options dictionary from the app delegate.
    public func start(launchOptions: [AnyHashable: Any]) {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Whether the device has successfully registered for remote notifications and received a device token.
    public var isRegisteredForRemoteNotifications: Bool {
        deviceToken != nil
    }

    /// The hex-encoded APNs device token used to identify this device for push notifications,
    /// or `nil` if registration has not yet completed.
    public var pushUserID: PushManagerUserID? {
        deviceToken
    }

    /// Requests a push notification user ID (the APNs device token).
    ///
    /// If a device token is already available, the callback is invoked immediately. Otherwise, the callback
    /// is queued and notification authorization is requested from the user. Once granted, the app registers
    /// for remote notifications, and all pending callbacks are invoked when the token arrives via
    /// ``didRegisterForRemoteNotifications(withDeviceToken:)``.
    ///
    /// - Parameter callback: A closure invoked with the hex-encoded device token string.
    public func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        if let deviceToken {
            callback(deviceToken)
            return
        }

        pendingCallbacks.append(callback)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            guard let self else { return }

            if let error {
                self.errorHandler?(error)
                return
            }

            guard granted else {
                self.errorHandler?(PushErrors.authorizationDenied)
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Device Token Handling

    /// Handles a successful remote notification registration.
    ///
    /// Converts the raw token data to a hex string, stores it, and invokes all pending callbacks.
    /// This method should be called from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    ///
    /// - Parameter tokenData: The raw APNs device token data provided by the system.
    @objc public func didRegisterForRemoteNotifications(withDeviceToken tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token

        Logger.info("APNs device token: \(token)")

        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll()
        for callback in callbacks {
            callback(token)
        }
    }

    /// Handles a failed remote notification registration.
    ///
    /// Logs the error, forwards it to ``errorHandler``, and clears all pending callbacks.
    /// This method should be called from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    ///
    /// - Parameter error: The error that prevented registration.
    @objc public func didFailToRegisterForRemoteNotifications(withError error: Error) {
        Logger.error("Failed to register for remote notifications: \(error)")
        errorHandler?(error)
        pendingCallbacks.removeAll()
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension OBACloudPushService: UNUserNotificationCenterDelegate {
    /// Displays notifications as a banner with sound when the app is in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Forwards the notification payload to ``notificationReceivedHandler`` when the user taps a notification.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let message = response.notification.request.content.body
        notificationReceivedHandler?(message, userInfo)
        completionHandler()
    }
}
