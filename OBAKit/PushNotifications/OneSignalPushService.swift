//
//  OneSignalClient.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/21/19.
//

import Foundation
import OneSignal
import CocoaLumberjackSwift

/// Push notification service wrapper for OneSignal, a free push notification service provider.
@objc(OBAOneSignalPushService)
public class OneSignalPushService: NSObject, PushServiceProvider {
    public var notificationReceivedHandler: PushServiceNotificationReceivedHandler!
    public var errorHandler: PushServiceErrorHandler!

    private let APIKey: String

    @objc public init(APIKey: String) {
        self.APIKey = APIKey
    }

    // MARK: - PushService Delegate

    public func start(launchOptions: [AnyHashable: Any]) {
        let settings: [String: Any] = [
            kOSSettingsKeyAutoPrompt: false,
            kOSSettingsKeyInAppAlerts: true,
            kOSSettingsKeyInFocusDisplayOption: OSNotificationDisplayType.notification.rawValue
        ]

        OneSignal.setLogLevel(.LL_ERROR, visualLevel: .LL_NONE)

        OneSignal.setLocationShared(false)

        OneSignal.initWithLaunchOptions(launchOptions, appId: APIKey, handleNotificationAction: handleNotificationAction(result:), settings: settings)
    }

    public var isRegisteredForRemoteNotifications: Bool {
        OneSignal.getPermissionSubscriptionState()?.permissionStatus.status == .authorized
    }

    public var pushUserID: PushManagerUserID? {
        OneSignal.getPermissionSubscriptionState()?.subscriptionStatus?.userId
    }

    public func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        OneSignal.promptForPushNotifications { [weak self] accepted in
            guard let self = self else { return }

            guard accepted else {
                self.errorHandler(PushErrors.authorizationDenied)
                return
            }

            guard
                let state = OneSignal.getPermissionSubscriptionState(),
                let subscriptionStatus = state.subscriptionStatus,
                let userID = subscriptionStatus.userId
            else {
                DDLogError("OneSignal failed to produce a user ID. Waiting!")
                return
            }
            callback(userID)
        }
    }

    private func handleNotificationAction(result: OSNotificationOpenedResult?) {
        guard
            let result = result,
            let message = result.notification.payload.body
        else { return }

        let additionalData = result.notification.payload.additionalData
        notificationReceivedHandler(message, additionalData)
    }
}
