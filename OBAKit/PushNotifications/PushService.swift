//
//  PushService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/20/19.
//

import Foundation
import UIKit
import OBAKitCore
import CocoaLumberjackSwift

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

//@objc(OBAPushServiceDelegate)
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

        if
            key == "arrival_and_departure",
            let data = additionalData["arrival_and_departure"] as? [String: Any],
            let pushBody = try? DictionaryDecoder.restApiServiceDecoder().decode(AlarmPushBody.self, from: data)
        {
            delegate?.pushService(self, received: pushBody)
            return
        }

        displayMessage(message)
    }

    private func displayMessage(_ message: String) {
        if let presentingController = delegate?.pushServicePresentingController(self) {
            AlertPresenter.showDismissableAlert(title: message, message: nil, presentingController: presentingController)
        }
    }

    private func errorHandler(error: Error) {
        DDLogError("Error received from push service: \(error)")
    }

    // MARK: - Public Methods

    @objc public func start(launchOptions: [AnyHashable: Any]) {
        serviceProvider.start(launchOptions: launchOptions)
    }

    @objc public func requestPushID(callback: @escaping PushManagerUserIDCallback) {
        serviceProvider.requestPushID(callback)
    }

    public var isRegisteredForRemoteNotifications: Bool {
        serviceProvider.isRegisteredForRemoteNotifications
    }

    public var pushUserID: PushManagerUserID? {
        serviceProvider.pushUserID
    }
}
