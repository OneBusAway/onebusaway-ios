//
//  PushServiceTests.swift
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
@Suite(.serialized)
final class PushServiceTests: OBATestCase {

    private var provider: RecordingPushServiceProvider!
    private var delegate: PushServiceDelegateRecorder!
    private var pushService: PushService!

    override init() async throws {
        try await super.init()

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

    @Test func `Init installs handlers on provider`() {
        #expect(provider.notificationReceivedHandler != nil)
        #expect(provider.errorHandler != nil)
    }

    @Test func `Start forwards launch options to provider`() {
        pushService.start(launchOptions: ["key": "value"])
        #expect((provider.startedLaunchOptions?["key"] as? String) == "value")
    }

    @Test func `Passthrough properties reflect provider`() {
        #expect(pushService.isRegisteredForRemoteNotifications)
        #expect(pushService.pushUserID == "mock-token")

        provider.stubbedPushUserID = nil
        provider.isRegisteredForRemoteNotifications = false

        #expect(!pushService.isRegisteredForRemoteNotifications)
        #expect(pushService.pushUserID == nil)
    }

    @Test func `Push ID async returns provider token`() async {
        let token = await pushService.pushID()
        #expect(token == "mock-token")
    }

    @Test func `Device token updates are forwarded to delegate`() {
        #expect(provider.deviceTokenUpdatedHandler != nil, "PushService must install the token handler during init")

        provider.deviceTokenUpdatedHandler?("01abff007f")

        #expect(delegate.receivedDeviceTokens == ["01abff007f"])
    }

    // MARK: - Alarm Payloads

    @Test func `Alarm payload is decoded and forwarded to delegate`() {
        provider.notificationReceivedHandler("Your bus is arriving soon!", ["arrival_and_departure": validAlarmPayload])

        #expect(delegate.receivedAlarms.count == 1)

        let alarm = delegate.receivedAlarms[0]
        #expect(alarm.tripID == "1_604387101")
        #expect(alarm.stopID == "1_75403")
        #expect(alarm.regionID == 1)
        #expect(alarm.vehicleID == "1_4361")
        #expect(alarm.stopSequence == 7)
        #expect(alarm.serviceDateEpochTimestamp == 1717027200000)
        #expect(alarm.serviceDate == Date(timeIntervalSince1970: 1717027200))
    }

    @Test func `Alarm payload without optional vehicle ID still decodes`() {
        var payload = validAlarmPayload
        payload.removeValue(forKey: "vehicle_id")

        provider.notificationReceivedHandler("Arriving", ["arrival_and_departure": payload])

        #expect(delegate.receivedAlarms.count == 1)
        #expect(delegate.receivedAlarms[0].vehicleID == nil)
    }

    @Test func `Malformed alarm payload does not call delegate or crash`() {
        provider.notificationReceivedHandler("Arriving", ["arrival_and_departure": ["trip_id": "only-this"]])

        #expect(delegate.receivedAlarms.isEmpty)
    }

    /// Real remote notifications always include `aps` alongside the custom
    /// data key (see `OBACloudPushService.userNotificationCenter(_:didReceive:...)`,
    /// which forwards the entire `UNNotificationContent.userInfo`). This
    /// mirrors that wire shape to guard against regressing to a strict
    /// single-key count.
    @Test func `Alarm payload with APS sibling is decoded and forwarded to delegate`() {
        provider.notificationReceivedHandler("Your bus is arriving soon!", [
            "aps": ["alert": ["body": "Your bus is arriving soon!"]],
            "arrival_and_departure": validAlarmPayload
        ])

        #expect(delegate.receivedAlarms.count == 1)

        let alarm = delegate.receivedAlarms[0]
        #expect(alarm.tripID == "1_604387101")
        #expect(alarm.stopID == "1_75403")
        #expect(alarm.regionID == 1)
        #expect(alarm.vehicleID == "1_4361")
        #expect(alarm.stopSequence == 7)
        #expect(alarm.serviceDateEpochTimestamp == 1717027200000)
        #expect(alarm.serviceDate == Date(timeIntervalSince1970: 1717027200))
    }

    // MARK: - Donation Payloads

    @Test func `Donation payload forwards test ID to delegate`() {
        provider.notificationReceivedHandler("Please donate", ["donation": "experiment-42"])

        #expect(delegate.receivedDonationPromptIDs.count == 1)
        #expect(delegate.receivedDonationPromptIDs[0] == "experiment-42")
    }

    @Test func `Donation payload with non string value forwards nil test ID`() {
        provider.notificationReceivedHandler("Please donate", ["donation": 123])

        #expect(delegate.receivedDonationPromptIDs.count == 1)
        #expect(delegate.receivedDonationPromptIDs[0] == nil)
    }

    /// Real remote notifications always include `aps` alongside the custom
    /// data key. Mirrors the wire shape delivered by
    /// `OBACloudPushService.userNotificationCenter(_:didReceive:...)`.
    @Test func `Donation payload with APS sibling forwards test ID to delegate`() {
        provider.notificationReceivedHandler("Please donate", [
            "aps": ["alert": ["body": "Please donate"]],
            "donation": "experiment-42"
        ])

        #expect(delegate.receivedDonationPromptIDs.count == 1)
        #expect(delegate.receivedDonationPromptIDs[0] == "experiment-42")
    }

    // MARK: - Fallback Paths

    @Test func `Multi key payload does not route to alarm or donation`() {
        provider.notificationReceivedHandler("Hello", ["a": 1, "b": 2])

        #expect(delegate.receivedAlarms.isEmpty)
        #expect(delegate.receivedDonationPromptIDs.isEmpty)
    }

    @Test func `Nil additional data does not route to alarm or donation`() {
        provider.notificationReceivedHandler("Hello", nil)

        #expect(delegate.receivedAlarms.isEmpty)
        #expect(delegate.receivedDonationPromptIDs.isEmpty)
    }

    @Test func `Unknown single key payload does not route to alarm or donation`() {
        provider.notificationReceivedHandler("Hello", ["unknown_key": "whatever"])

        #expect(delegate.receivedAlarms.isEmpty)
        #expect(delegate.receivedDonationPromptIDs.isEmpty)
    }

    /// A plain service alert notification has no custom data key at all —
    /// just the standard `aps` payload — and should fall through to display.
    @Test func `Aps only payload does not route to alarm or donation`() {
        provider.notificationReceivedHandler("Service alert", [
            "aps": ["alert": ["body": "Service alert"]]
        ])

        #expect(delegate.receivedAlarms.isEmpty)
        #expect(delegate.receivedDonationPromptIDs.isEmpty)
    }

    /// Two custom keys alongside `aps` is an ambiguous payload; it should
    /// still fall through to display rather than guessing which key wins.
    @Test func `Two custom keys with APS sibling does not route to alarm or donation`() {
        provider.notificationReceivedHandler("Hello", [
            "aps": ["alert": ["body": "Hello"]],
            "arrival_and_departure": validAlarmPayload,
            "donation": "experiment-42"
        ])

        #expect(delegate.receivedAlarms.isEmpty)
        #expect(delegate.receivedDonationPromptIDs.isEmpty)
    }
}
