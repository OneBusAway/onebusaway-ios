//
//  PushServiceTests.swift
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

// MARK: - Test Doubles

private class RecordingPushServiceProvider: NSObject, PushServiceProvider {
    var notificationReceivedHandler: PushServiceNotificationReceivedHandler!
    var errorHandler: PushServiceErrorHandler!

    var startedLaunchOptions: [AnyHashable: Any]?
    var stubbedPushUserID: PushManagerUserID? = "mock-token"
    var isRegisteredForRemoteNotifications: Bool = true
    var deviceTokenUpdatedHandler: PushServiceDeviceTokenCallback?

    func start(launchOptions: [AnyHashable: Any]) {
        startedLaunchOptions = launchOptions
    }

    func requestPushID(_ callback: @escaping PushManagerUserIDCallback) {
        callback(stubbedPushUserID ?? "mock-token")
    }

    var pushUserID: PushManagerUserID? {
        stubbedPushUserID
    }
}

private class PushServiceDelegateRecorder: NSObject, PushServiceDelegate {
    var receivedAlarms: [AlarmPushBody] = []
    var receivedDonationPromptIDs: [String?] = []
    var receivedDeviceTokens: [String] = []

    func pushServicePresentingController(_ pushService: PushService) -> UIViewController? {
        nil
    }

    func pushService(_ pushService: PushService, received arrivalDeparture: AlarmPushBody) {
        receivedAlarms.append(arrivalDeparture)
    }

    func pushService(_ pushService: PushService, receivedDonationPrompt id: String?) {
        receivedDonationPromptIDs.append(id)
    }

    func pushService(_ pushService: PushService, receivedDeviceToken token: String) {
        receivedDeviceTokens.append(token)
    }
}

// MARK: - Tests

/// Tests for `PushService`'s routing of incoming push notification payloads:
/// alarm (`arrival_and_departure`) payload decoding, donation prompts, and
/// graceful handling of malformed payloads.
class PushServiceTests: OBATestCase {

    private var provider: RecordingPushServiceProvider!
    private var delegate: PushServiceDelegateRecorder!
    private var pushService: PushService!

    override func setUp() async throws {
        try await super.setUp()
        provider = RecordingPushServiceProvider()
        delegate = PushServiceDelegateRecorder()
        pushService = PushService(serviceProvider: provider, delegate: delegate)
    }

    private var validAlarmPayload: [String: Any] {
        [
            "trip_id": "1_604387101",
            "stop_id": "1_75403",
            "region_id": 1,
            "vehicle_id": "1_4361",
            "service_date": 1717027200000 as Int64,
            "stop_sequence": 7
        ]
    }

    // MARK: - Wiring

    func test_init_installsHandlersOnProvider() {
        XCTAssertNotNil(provider.notificationReceivedHandler)
        XCTAssertNotNil(provider.errorHandler)
    }

    func test_start_forwardsLaunchOptionsToProvider() {
        pushService.start(launchOptions: ["key": "value"])
        XCTAssertEqual(provider.startedLaunchOptions?["key"] as? String, "value")
    }

    func test_passthroughProperties_reflectProvider() {
        XCTAssertTrue(pushService.isRegisteredForRemoteNotifications)
        XCTAssertEqual(pushService.pushUserID, "mock-token")

        provider.stubbedPushUserID = nil
        provider.isRegisteredForRemoteNotifications = false

        XCTAssertFalse(pushService.isRegisteredForRemoteNotifications)
        XCTAssertNil(pushService.pushUserID)
    }

    func test_pushID_asyncReturnsProviderToken() async {
        let token = await pushService.pushID()
        XCTAssertEqual(token, "mock-token")
    }

    func test_deviceTokenUpdates_areForwardedToDelegate() {
        XCTAssertNotNil(provider.deviceTokenUpdatedHandler, "PushService must install the token handler during init")

        provider.deviceTokenUpdatedHandler?("01abff007f")

        XCTAssertEqual(delegate.receivedDeviceTokens, ["01abff007f"])
    }

    // MARK: - Alarm Payloads

    func test_alarmPayload_isDecodedAndForwardedToDelegate() {
        provider.notificationReceivedHandler("Your bus is arriving soon!", ["arrival_and_departure": validAlarmPayload])

        XCTAssertEqual(delegate.receivedAlarms.count, 1)

        let alarm = delegate.receivedAlarms[0]
        XCTAssertEqual(alarm.tripID, "1_604387101")
        XCTAssertEqual(alarm.stopID, "1_75403")
        XCTAssertEqual(alarm.regionID, 1)
        XCTAssertEqual(alarm.vehicleID, "1_4361")
        XCTAssertEqual(alarm.stopSequence, 7)
        XCTAssertEqual(alarm.serviceDateEpochTimestamp, 1717027200000)
        XCTAssertEqual(alarm.serviceDate, Date(timeIntervalSince1970: 1717027200))
    }

    func test_alarmPayload_withoutOptionalVehicleID_stillDecodes() {
        var payload = validAlarmPayload
        payload.removeValue(forKey: "vehicle_id")

        provider.notificationReceivedHandler("Arriving", ["arrival_and_departure": payload])

        XCTAssertEqual(delegate.receivedAlarms.count, 1)
        XCTAssertNil(delegate.receivedAlarms[0].vehicleID)
    }

    func test_malformedAlarmPayload_doesNotCallDelegateOrCrash() {
        provider.notificationReceivedHandler("Arriving", ["arrival_and_departure": ["trip_id": "only-this"]])

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
    }

    /// Real remote notifications always include `aps` alongside the custom
    /// data key (see `OBACloudPushService.userNotificationCenter(_:didReceive:...)`,
    /// which forwards the entire `UNNotificationContent.userInfo`). This
    /// mirrors that wire shape to guard against regressing to a strict
    /// single-key count.
    func test_alarmPayloadWithAPSSibling_isDecodedAndForwardedToDelegate() {
        provider.notificationReceivedHandler("Your bus is arriving soon!", [
            "aps": ["alert": ["body": "Your bus is arriving soon!"]],
            "arrival_and_departure": validAlarmPayload
        ])

        XCTAssertEqual(delegate.receivedAlarms.count, 1)

        let alarm = delegate.receivedAlarms[0]
        XCTAssertEqual(alarm.tripID, "1_604387101")
        XCTAssertEqual(alarm.stopID, "1_75403")
        XCTAssertEqual(alarm.regionID, 1)
        XCTAssertEqual(alarm.vehicleID, "1_4361")
        XCTAssertEqual(alarm.stopSequence, 7)
        XCTAssertEqual(alarm.serviceDateEpochTimestamp, 1717027200000)
        XCTAssertEqual(alarm.serviceDate, Date(timeIntervalSince1970: 1717027200))
    }

    // MARK: - Donation Payloads

    func test_donationPayload_forwardsTestIDToDelegate() {
        provider.notificationReceivedHandler("Please donate", ["donation": "experiment-42"])

        XCTAssertEqual(delegate.receivedDonationPromptIDs.count, 1)
        XCTAssertEqual(delegate.receivedDonationPromptIDs[0], "experiment-42")
    }

    func test_donationPayload_withNonStringValue_forwardsNilTestID() {
        provider.notificationReceivedHandler("Please donate", ["donation": 123])

        XCTAssertEqual(delegate.receivedDonationPromptIDs.count, 1)
        XCTAssertNil(delegate.receivedDonationPromptIDs[0])
    }

    /// Real remote notifications always include `aps` alongside the custom
    /// data key. Mirrors the wire shape delivered by
    /// `OBACloudPushService.userNotificationCenter(_:didReceive:...)`.
    func test_donationPayloadWithAPSSibling_forwardsTestIDToDelegate() {
        provider.notificationReceivedHandler("Please donate", [
            "aps": ["alert": ["body": "Please donate"]],
            "donation": "experiment-42"
        ])

        XCTAssertEqual(delegate.receivedDonationPromptIDs.count, 1)
        XCTAssertEqual(delegate.receivedDonationPromptIDs[0], "experiment-42")
    }

    // MARK: - Fallback Paths

    func test_multiKeyPayload_doesNotRouteToAlarmOrDonation() {
        provider.notificationReceivedHandler("Hello", ["a": 1, "b": 2])

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
        XCTAssertTrue(delegate.receivedDonationPromptIDs.isEmpty)
    }

    func test_nilAdditionalData_doesNotRouteToAlarmOrDonation() {
        provider.notificationReceivedHandler("Hello", nil)

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
        XCTAssertTrue(delegate.receivedDonationPromptIDs.isEmpty)
    }

    func test_unknownSingleKeyPayload_doesNotRouteToAlarmOrDonation() {
        provider.notificationReceivedHandler("Hello", ["unknown_key": "whatever"])

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
        XCTAssertTrue(delegate.receivedDonationPromptIDs.isEmpty)
    }

    /// A plain service alert notification has no custom data key at all —
    /// just the standard `aps` payload — and should fall through to display.
    func test_apsOnlyPayload_doesNotRouteToAlarmOrDonation() {
        provider.notificationReceivedHandler("Service alert", [
            "aps": ["alert": ["body": "Service alert"]]
        ])

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
        XCTAssertTrue(delegate.receivedDonationPromptIDs.isEmpty)
    }

    /// Two custom keys alongside `aps` is an ambiguous payload; it should
    /// still fall through to display rather than guessing which key wins.
    func test_twoCustomKeysWithAPSSibling_doesNotRouteToAlarmOrDonation() {
        provider.notificationReceivedHandler("Hello", [
            "aps": ["alert": ["body": "Hello"]],
            "arrival_and_departure": validAlarmPayload,
            "donation": "experiment-42"
        ])

        XCTAssertTrue(delegate.receivedAlarms.isEmpty)
        XCTAssertTrue(delegate.receivedDonationPromptIDs.isEmpty)
    }
}
