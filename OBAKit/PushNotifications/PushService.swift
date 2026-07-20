//
//  PushService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import OBAKitCore

// MARK: - Types

public typealias PushManagerUserID = String
public typealias PushManagerUserIDCallback = ((PushManagerUserID) -> Void)
public typealias PushServiceNotificationReceivedHandler = ((String, [AnyHashable: Any]?) -> Void)
public typealias PushServiceErrorHandler = ((Error) -> Void)
/// Carries the hex-encoded APNs device token (distinct from a provider's push user ID).
public typealias PushServiceDeviceTokenCallback = (String) -> Void

// MARK: - Errors

public enum PushErrors: Error {
    case authorizationDenied
}

// MARK: - PushServiceProvider Protocol

@objc(OBAPushServiceProvider)
public protocol PushServiceProvider: NSObjectProtocol {
    var isRegisteredForRemoteNotifications: Bool { get }

    func start(launchOptions: [AnyHashable: Any])
    func requestPushID(_ callback: @escaping PushManagerUserIDCallback)

    var notificationReceivedHandler: PushServiceNotificationReceivedHandler! { get set }
    var errorHandler: PushServiceErrorHandler! { get set }

    /// Called with the hex-encoded APNs token every time the device (re-)registers with APNs,
    /// including token rotations. Set by ``PushService`` during initialization.
    var deviceTokenUpdatedHandler: PushServiceDeviceTokenCallback? { get set }

    var pushUserID: PushManagerUserID? { get }
}

// MARK: - PushServiceDelegate

public protocol PushServiceDelegate: NSObjectProtocol {
    func pushServicePresentingController(_ pushService: PushService) -> UIViewController?
    func pushService(_ pushService: PushService, received arrivalDeparture: AlarmPushBody)
    func pushService(_ pushService: PushService, receivedDonationPrompt id: String?)

    /// Called whenever APNs issues the device a (possibly rotated) push token.
    func pushService(_ pushService: PushService, receivedDeviceToken token: String)
}

// MARK: - PushService

@objc(OBAPushService)
public class PushService: NSObject {
    private let serviceProvider: PushServiceProvider

    public weak var delegate: PushServiceDelegate?

    public init(serviceProvider: PushServiceProvider, delegate: PushServiceDelegate?) {
        self.serviceProvider = serviceProvider
        self.delegate = delegate

        super.init()

        self.serviceProvider.notificationReceivedHandler = notificationReceivedHandler(message:additionalData:)
        self.serviceProvider.errorHandler = errorHandler(error:)
        self.serviceProvider.deviceTokenUpdatedHandler = { [weak self] token in
            guard let self else { return }
            self.delegate?.pushService(self, receivedDeviceToken: token)
        }
    }

    // MARK: - PushServiceProvider Callbacks

    private func notificationReceivedHandler(message: String, additionalData: [AnyHashable: Any]?) {
        // Remote-notification `userInfo` always includes an `aps` entry alongside
        // any custom data key (see OBACloudPushService.userNotificationCenter(_:didReceive:...),
        // which forwards the entire UNNotificationContent.userInfo). Routing must
        // therefore count only the custom keys, ignoring `aps`, rather than requiring
        // the whole dictionary to contain exactly one key.
        let customKeys = (additionalData ?? [:]).keys.compactMap { $0 as? String }.filter { $0 != "aps" }
        guard let additionalData, customKeys.count == 1, let key = customKeys.first else {
            displayMessage(message)

            return
        }

        if key == "arrival_and_departure", let data = additionalData["arrival_and_departure"] as? [String: Any] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                let pushBody = try JSONDecoder().decode(AlarmPushBody.self, from: jsonData)
                delegate?.pushService(self, received: pushBody)
            } catch let error {
                Logger.error("Error decoding AlarmPushBody: \(error)")
            }
            return
        }
        else if key == "donation" {
            let testID = additionalData["donation"] as? String
            delegate?.pushService(self, receivedDonationPrompt: testID)
        }
        else {
            displayMessage(message)
        }
    }

    private func displayMessage(_ message: String) {
        Task { @MainActor in
            if let presentingController = delegate?.pushServicePresentingController(self) {
                await AlertPresenter.showDismissableAlert(title: message, message: nil, presentingController: presentingController)
            }
        }
    }

    private func errorHandler(error: Error) {
        Logger.error("Error received from push service: \(error)")
    }

    // MARK: - Public Methods

    @objc public func start(launchOptions: [AnyHashable: Any]) {
        serviceProvider.start(launchOptions: launchOptions)
    }

    @objc public func requestPushID(callback: @escaping PushManagerUserIDCallback) {
        serviceProvider.requestPushID(callback)
    }

    public func pushID() async -> PushManagerUserID {
        await withCheckedContinuation { continuation in
            serviceProvider.requestPushID { userID in
                continuation.resume(returning: userID)
            }
        }
    }

    public var isRegisteredForRemoteNotifications: Bool {
        serviceProvider.isRegisteredForRemoteNotifications
    }

    public var pushUserID: PushManagerUserID? {
        serviceProvider.pushUserID
    }
}
