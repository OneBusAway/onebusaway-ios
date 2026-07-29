//
//  AlarmModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

@Suite(.serialized)
final class AlarmModelOperationTests: OBATestCase {

    /// Captures the body of the request the service actually put on the wire. Single
    /// request per test, written before the mock returns and read after the `await`
    /// resumes, so there's no concurrent access in practice.
    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var body: String?
    }

    @Test func `Successful alarm creation`() async throws {
        let data = Fixtures.loadData(file: "create_alarm.json")
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(type: ArrivalDeparture.self, fileName: "arrival-and-departure-for-stop-1_11420.json")

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(URLString: "https://alerts.example.com/api/v2/regions/1/alarms", with: data)

        let alarm = try await obacoService.postAlarm(minutesBefore: 1, arrivalDeparture: arrivalDeparture, userPushID: "123")
        #expect(alarm.url.absoluteString == "https://alerts.example.com/regions/1/alarms/1234567890")
    }

    /// A debug build is provisioned with the development APNs entitlement, so the token
    /// APNs issues it is a sandbox token. The server pushes to production APNs by config,
    /// which rejects that token — the alarm silently never arrives. Registration therefore
    /// flags the alarm, and the server pushes it through the APNs sandbox instead.
    ///
    /// The test suite only ever builds in Debug, so `#if DEBUG` is always true here; this
    /// pins the flag's presence and wire format, not the compile-time condition itself.
    @Test func `Alarm creation flags development builds`() async throws {
        let data = Fixtures.loadData(file: "create_alarm.json")
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(type: ArrivalDeparture.self, fileName: "arrival-and-departure-for-stop-1_11420.json")

        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: data) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/alarms") ?? false else {
                return false
            }
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            return true
        }

        _ = try await obacoService.postAlarm(minutesBefore: 1, arrivalDeparture: arrivalDeparture, userPushID: "123")

        let body = try #require(capture.body, "Expected postAlarm to send a form-encoded body")
        #expect(body.contains("apns_sandbox=1"), "Expected a debug build to flag the alarm for the APNs sandbox. Body: \(body)")
    }

    /// The sidecar answers a successful `DELETE` with an empty `204`.
    @Test func `Successful alarm deletion`() async throws {
        let alarm = try Fixtures.loadAlarm()
        #expect(alarm != nil)

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        // Hoisted out of the closure: matchers are @Sendable and `Alarm` is not,
        // so the closure must capture the string rather than the model.
        let alarmURLString = alarm.url.absoluteString
        dataLoader.mock(data: Data(), statusCode: 204) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarmURLString) &&
            request.httpMethod == "DELETE"
        }

        let (_, response) = try await obacoService.deleteAlarm(url: alarm.url)
        let httpResponse = try #require(response as? HTTPURLResponse, "Expected deleteAlarm response to be of type HTTPURLResponse")
        #expect(httpResponse.statusCode == 204)
    }

    /// Sidecars predating the switch to `204` answer a successful `DELETE` with an empty
    /// `200`. `APIService.data(for:)` reads an empty-bodied `200` as a disguised 404 — a
    /// workaround for the REST API's handling of bogus IDs — which turned every successful
    /// alarm cancel into a `requestNotFound` failure. That heuristic must not apply here.
    @Test func `Successful alarm deletion with empty 200`() async throws {
        let alarm = try Fixtures.loadAlarm()

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        // Hoisted out of the closure: matchers are @Sendable and `Alarm` is not,
        // so the closure must capture the string rather than the model.
        let alarmURLString = alarm.url.absoluteString
        dataLoader.mock(data: Data(), statusCode: 200) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarmURLString) &&
            request.httpMethod == "DELETE"
        }

        let (_, response) = try await obacoService.deleteAlarm(url: alarm.url)
        let httpResponse = try #require(response as? HTTPURLResponse, "Expected deleteAlarm response to be of type HTTPURLResponse")
        #expect(httpResponse.statusCode == 200)
    }

    /// A genuine 404 — the alarm is already gone — must still surface as `requestNotFound`.
    @Test func `Alarm deletion with 404`() async throws {
        let alarm = try Fixtures.loadAlarm()

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        // Hoisted out of the closure: matchers are @Sendable and `Alarm` is not,
        // so the closure must capture the string rather than the model.
        let alarmURLString = alarm.url.absoluteString
        dataLoader.mock(data: Data(), statusCode: 404) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarmURLString) &&
            request.httpMethod == "DELETE"
        }

        do {
            _ = try await obacoService.deleteAlarm(url: alarm.url)
            Issue.record("Expected deleteAlarm to throw APIError.requestNotFound")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                Issue.record("Expected APIError.requestNotFound, got \(error)")
                return
            }
        }
    }
}
