//
//  PushService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/20/19.
//

import Foundation

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
}

// MARK: - PushService

@objc(OBAPushService)
public class PushService: NSObject {
    private let serviceProvider: PushServiceProvider

    public init(serviceProvider: PushServiceProvider) {
        self.serviceProvider = serviceProvider

        super.init()

        self.serviceProvider.notificationReceivedHandler = notificationReceivedHandler(message:additionalData:)
        self.serviceProvider.errorHandler = errorHandler(error:)
    }

    // MARK: - PushServiceProvider Callbacks

    private func notificationReceivedHandler(message: String, additionalData: [AnyHashable: Any]?) {
        //
    }

    private func errorHandler(error: Error) {
        //
    }

    // MARK: - Public Methods

    @objc public func start(launchOptions: [AnyHashable: Any]) {
        serviceProvider.start(launchOptions: launchOptions)
    }
}
