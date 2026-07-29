//
//  OBACloudPushServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `OBACloudPushService`, the direct-APNs replacement for OneSignal.
///
/// These tests cover the device-token lifecycle: hex conversion, pending callback
/// delivery, and failure handling. They deliberately avoid asserting on anything
/// driven by `UNUserNotificationCenter.requestAuthorization`, whose behavior is
/// simulator- and permission-state-dependent.
@Suite(.serialized)
final class OBACloudPushServiceTests: OBATestCase {

    private var service: OBACloudPushService!

    override init() async throws {
        try await super.init()

        service = OBACloudPushService()
        // The real handlers are installed by PushService during init. Install benign
        // defaults so an async authorization denial can never crash a test.
        service.notificationReceivedHandler = { _, _ in }
        service.errorHandler = { _ in }
    }

    // MARK: - Token Conversion

    @Test func `Did register converts token data to lowercase hex string`() {
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0x01, 0xAB, 0xFF, 0x00, 0x7F]))

        #expect(service.pushUserID == "01abff007f")
        #expect(service.isRegisteredForRemoteNotifications)
    }

    @Test func `Before registration no token is available`() {
        #expect(service.pushUserID == nil)
        #expect(!service.isRegisteredForRemoteNotifications)
    }

    // MARK: - Callback Delivery

    @Test func `Request push ID with existing token invokes callback immediately`() {
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xDE, 0xAD]))

        var receivedTokens: [String] = []
        service.requestPushID { receivedTokens.append($0) }

        #expect(receivedTokens == ["dead"])
    }

    @Test func `Did register delivers all pending callbacks exactly once`() {
        var firstTokens: [String] = []
        var secondTokens: [String] = []
        service.requestPushID { firstTokens.append($0) }
        service.requestPushID { secondTokens.append($0) }

        #expect(firstTokens.isEmpty, "Callbacks must not fire before a token arrives")

        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))

        #expect(firstTokens == ["beef"])
        #expect(secondTokens == ["beef"])

        // A re-registration (token rotation) must not re-invoke already-delivered callbacks.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

        #expect(firstTokens == ["beef"])
        #expect(secondTokens == ["beef"])
        #expect(service.pushUserID == "cafe")
    }

    // MARK: - Failure Handling

    @Test func `Did fail forwards error and clears pending callbacks`() {
        var receivedErrors: [Error] = []
        service.errorHandler = { receivedErrors.append($0) }

        var receivedTokens: [String] = []
        service.requestPushID { receivedTokens.append($0) }

        let registrationError = NSError(domain: "test", code: 3000, userInfo: nil)
        service.didFailToRegisterForRemoteNotifications(withError: registrationError)

        #expect(receivedErrors.count == 1)
        #expect((receivedErrors.first as NSError?)?.code == 3000)

        // A token arriving after failure must not invoke the cleared callbacks.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0x11]))
        #expect(receivedTokens.isEmpty)
    }

    // MARK: - Token Update Handler

    @Test func `Did register invokes device token updated handler on every registration`() {
        var receivedTokens: [String] = []
        service.deviceTokenUpdatedHandler = { receivedTokens.append($0) }

        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))
        // Token rotation (restore/reinstall) re-fires the handler with the new token.
        service.didRegisterForRemoteNotifications(withDeviceToken: Data([0xCA, 0xFE]))

        #expect(receivedTokens == ["beef", "cafe"])
    }
}
