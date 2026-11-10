//
//  AlarmBuilderTests.swift
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

/// What happens when the rider taps Add Alarm. The picker page and its Track on
/// Lock Screen switch are covered by `AlarmTimePickerItemTests`; these tests
/// start from the lead time the picker hands to `createAlarm(minutes:)`.
@MainActor
@Suite(.serialized)
final class AlarmBuilderTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// Records what the builder reports. Dismisses the HUD the way the real
    /// delegates do, since the builder hands it over with each call.
    private final class RecordingDelegate: NSObject, AlarmBuilderDelegate {
        var created: [Alarm] = []
        var errors: [Error] = []

        func alarmBuilder(_ alarmBuilder: AlarmBuilder, alarmCreated alarm: Alarm) {
            created.append(alarm)
            ProgressHUD.dismiss()
        }

        func alarmBuilder(_ alarmBuilder: AlarmBuilder, error: Error) {
            errors.append(error)
            ProgressHUD.dismiss()
        }
    }

    /// The bodies of the alarm requests the sidecar received. Written by the
    /// loader's matcher before it responds and read after the `await` returns.
    private final class AlarmRequests: @unchecked Sendable {
        nonisolated(unsafe) var bodies: [String] = []
    }

    /// Stubs the sidecar's alarm endpoint, answering with `statusCode`.
    private func stubAlarms(_ loader: MockDataLoader, statusCode: Int = 200) -> AlarmRequests {
        let requests = AlarmRequests()
        let data = statusCode == 200 ? Fixtures.loadData(file: "create_alarm.json") : Data()
        loader.mock(data: data, statusCode: statusCode) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/alarms") ?? false else {
                return false
            }
            requests.bodies.append(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            return true
        }
        return requests
    }

    /// An app in Puget Sound, whose region has a sidecar, so `obacoService`
    /// exists. `withPushService` stands in for what launch sets up.
    private func buildApp(_ loader: MockDataLoader, withPushService: Bool = true) throws -> Application {
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let app = buildApplication(queue: queue, dataLoader: loader)
        if withPushService {
            app.pushService = PushService(serviceProvider: MockPushServiceProvider(), delegate: app)
        }
        try #require(app.currentRegion != nil)
        try #require(app.obacoService != nil)
        return app
    }

    private func departure() throws -> ArrivalDeparture {
        try Fixtures.loadRESTAPIPayload(type: ArrivalDeparture.self, fileName: "arrival-and-departure-for-stop-1_11420.json")
    }

    /// The form-encoded value of `key` in a request body.
    private func value(_ key: String, in body: String) -> String? {
        URLComponents(string: "?" + body)?.queryItems?.first { $0.name == key }?.value
    }

    // MARK: - Tests

    @Test func `Adding an alarm posts the chosen lead time and links the alarm to the trip`() async throws {
        let loader = MockDataLoader(testName: name)
        let requests = stubAlarms(loader)
        let app = try buildApp(loader)
        let departure = try departure()
        let delegate = RecordingDelegate()
        let builder = AlarmBuilder(arrivalDeparture: departure, application: app, delegate: delegate)

        await builder.createAlarm(minutes: 7)

        #expect(requests.bodies.count == 1)
        let body = try #require(requests.bodies.first)
        #expect(value("seconds_before", in: body).flatMap(Double.init) == 420)
        #expect(value("trip_id", in: body) == departure.tripID)

        #expect(delegate.errors.isEmpty)
        let alarm = try #require(delegate.created.first)
        #expect(alarm.alarmDate == departure.arrivalDepartureDate.addingTimeInterval(-420))
        #expect(alarm.deepLink?.tripID == departure.tripID)
        #expect(alarm.deepLink?.regionID == app.currentRegion?.regionIdentifier)
    }

    @Test func `A failed alarm request tells the delegate and creates no alarm`() async throws {
        let loader = MockDataLoader(testName: name)
        let requests = stubAlarms(loader, statusCode: 500)
        let app = try buildApp(loader)
        let delegate = RecordingDelegate()
        let builder = AlarmBuilder(arrivalDeparture: try departure(), application: app, delegate: delegate)

        await builder.createAlarm(minutes: 7)

        #expect(requests.bodies.count == 1)
        #expect(delegate.created.isEmpty)
        #expect(delegate.errors.count == 1)
        let error = try #require(delegate.errors.first as? AlarmBuilder.AlarmBuilderErrors)
        #expect(error == .creationFailed)
    }

    /// The sidecar sends the alarm as a push, so without a push ID there's
    /// nothing to register. Today the builder returns without telling its
    /// delegate; this test deliberately doesn't pin that, only that nothing
    /// is posted or created.
    @Test func `Without a push service no alarm is posted or created`() async throws {
        let loader = MockDataLoader(testName: name)
        let requests = stubAlarms(loader)
        let app = try buildApp(loader, withPushService: false)
        let delegate = RecordingDelegate()
        let builder = AlarmBuilder(arrivalDeparture: try departure(), application: app, delegate: delegate)

        await builder.createAlarm(minutes: 7)

        #expect(requests.bodies.isEmpty)
        #expect(delegate.created.isEmpty)
    }

    /// Add Alarm stays tappable while the request is in flight. Both calls start
    /// before either finishes, as a quick double tap would.
    @Test func `A second tap while the first is in flight posts one alarm`() async throws {
        let loader = MockDataLoader(testName: name)
        let requests = stubAlarms(loader)
        let app = try buildApp(loader)
        let delegate = RecordingDelegate()
        let builder = AlarmBuilder(arrivalDeparture: try departure(), application: app, delegate: delegate)

        async let first: Void = builder.createAlarm(minutes: 7)
        async let second: Void = builder.createAlarm(minutes: 7)
        _ = await (first, second)

        #expect(requests.bodies.count == 1)
        #expect(delegate.created.count == 1)
    }
}
