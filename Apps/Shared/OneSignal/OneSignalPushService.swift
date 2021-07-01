//
//  OneSignalClient.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OneSignal
import OBAKit
import OBAKitCore

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
        OneSignal.setLogLevel(.LL_ERROR, visualLevel: .LL_NONE)

        OneSignal.setLocationShared(false)

        OneSignal.initWithLaunchOptions(launchOptions)
        OneSignal.setAppId(APIKey)
        OneSignal.setNotificationOpenedHandler(handleNotificationAction(result:))
    }

    public var isRegisteredForRemoteNotifications: Bool {
        deviceState.notificationPermissionStatus == .authorized
    }

    public var pushUserID: PushManagerUserID? {
        deviceState.userId
    }
    
    private var deviceState: OSDeviceState {
        OneSignal.getDeviceState()
    }

    public func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        OneSignal.promptForPushNotifications { [weak self] accepted in
            guard let self = self else { return }

            guard accepted else {
                self.errorHandler(PushErrors.authorizationDenied)
                return
            }

            guard self.deviceState.isSubscribed, let userID = self.deviceState.userId else {
                Logger.error("OneSignal failed to produce a user ID. Waiting!")
                return
            }

            callback(userID)
        }
    }

    private func handleNotificationAction(result: OSNotificationOpenedResult) {
        guard let message = result.notification.body else {
            return
        }

        let additionalData = result.notification.additionalData
        notificationReceivedHandler(message, additionalData)
    }
}
