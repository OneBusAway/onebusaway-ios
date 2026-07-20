//
//  OBACloudPushServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `OBACloudPushService`, the direct-APNs replacement for OneSignal.
///
/// These tests cover the device-token lifecycle: hex conversion, pending callback
/// delivery, and failure handling. They deliberately avoid asserting on anything
/// driven by `UNUserNotificationCenter.requestAuthorization`, whose behavior is
/// simulator- and permission-state-dependent.
class OBACloudPushServiceTests: OBATestCase {

    private var service: OBACloudPushService!

    override func setUp() async throws {
        try await super.setUp()
        service = OBACloudPushService()
        // The real handlers are installed by PushService during init. Install benign
        // defaults so an async authorization denial can never crash a test.
        service.notificationReceivedHandler = { _, _ in }
        service.errorHandler = { _ in }
    }

    // MARK: - Token Conversion

    func test_didRegister_convertsTokenDataToLowercaseHexString() {
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0x01, 0xAB, 0xFF, 0x00, 0x7F]))

        XCTAssertEqual(service.pushUserID, "01abff007f")
        XCTAssertTrue(service.isRegisteredForRemoteNotifications)
    }

    func test_beforeRegistration_noTokenIsAvailable() {
        XCTAssertNil(service.pushUserID)
        XCTAssertFalse(service.isRegisteredForRemoteNotifications)
    }

    // MARK: - Callback Delivery

    func test_requestPushID_withExistingToken_invokesCallbackImmediately() {
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xDE, 0xAD]))

        var receivedTokens: [String] = []
        service.requestPushID { receivedTokens.append($0) }

        XCTAssertEqual(receivedTokens, ["dead"])
    }

    func test_didRegister_deliversAllPendingCallbacksExactlyOnce() {
        var firstTokens: [String] = []
        var secondTokens: [String] = []
        service.requestPushID { firstTokens.append($0) }
        service.requestPushID { secondTokens.append($0) }

        XCTAssertTrue(firstTokens.isEmpty, "Callbacks must not fire before a token arrives")

        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))

        XCTAssertEqual(firstTokens, ["beef"])
        XCTAssertEqual(secondTokens, ["beef"])

        // A re-registration (token rotation) must not re-invoke already-delivered callbacks.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

        XCTAssertEqual(firstTokens, ["beef"])
        XCTAssertEqual(secondTokens, ["beef"])
        XCTAssertEqual(service.pushUserID, "cafe")
    }

    // MARK: - Failure Handling

    func test_didFail_forwardsErrorAndClearsPendingCallbacks() {
        var receivedErrors: [Error] = []
        service.errorHandler = { receivedErrors.append($0) }

        var receivedTokens: [String] = []
        service.requestPushID { receivedTokens.append($0) }

        let registrationError = NSError(domain: "test", code: 3000, userInfo: nil)
        service.didFailToRegisterForRemoteNotifications(withError: registrationError)

        XCTAssertEqual(receivedErrors.count, 1)
        XCTAssertEqual((receivedErrors.first as NSError?)?.code, 3000)

        // A token arriving after failure must not invoke the cleared callbacks.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0x11]))
        XCTAssertTrue(receivedTokens.isEmpty)
    }

    // MARK: - Token Update Handler

    func test_didRegister_invokesDeviceTokenUpdatedHandlerOnEveryRegistration() {
        var receivedTokens: [String] = []
        service.deviceTokenUpdatedHandler = { receivedTokens.append($0) }

        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))
        // Token rotation (restore/reinstall) re-fires the handler with the new token.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

        XCTAssertEqual(receivedTokens, ["beef", "cafe"])
    }
}
