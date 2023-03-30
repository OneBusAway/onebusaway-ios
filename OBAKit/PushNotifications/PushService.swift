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

    var pushUserID: PushManagerUserID? { get }
}

// MARK: - PushServiceDelegate

public protocol PushServiceDelegate: NSObjectProtocol {
    func pushServicePresentingController(_ pushService: PushService) -> UIViewController?
    func pushService(_ pushService: PushService, received arrivalDeparture: AlarmPushBody)
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
    }

    // MARK: - PushServiceProvider Callbacks

    private func notificationReceivedHandler(message: String, additionalData: [AnyHashable: Any]?) {
        guard
            let additionalData = additionalData,
            additionalData.keys.count == 1,
            let key = additionalData.keys.first as? String
        else {
            displayMessage(message)

            return
        }

        if key == "arrival_and_departure", let data = additionalData["arrival_and_departure"] as? [String: Any] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                let pushBody = try JSONDecoder().decode(AlarmPushBody.self, from: jsonData)
                delegate?.pushService(self, received: pushBody)
            } catch let error {
                print("Error decoding AlarmPushBody: \(error)")
            }
            return
        }

        displayMessage(message)
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
