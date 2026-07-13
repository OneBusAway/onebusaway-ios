//
//  AlarmModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

class AlarmModelOperationTests: OBATestCase {

    func testSuccessfulAlarmCreation() async throws {
        let data = Fixtures.loadData(file: "create_alarm.json")
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(type: ArrivalDeparture.self, fileName: "arrival-and-departure-for-stop-1_11420.json")

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(URLString: "https://alerts.example.com/api/v2/regions/1/alarms", with: data)

        let alarm = try await obacoService.postAlarm(minutesBefore: 1, arrivalDeparture: arrivalDeparture, userPushID: "123")
        XCTAssertEqual(alarm.url.absoluteString, "https://alerts.example.com/regions/1/alarms/1234567890")
    }

    /// The sidecar answers a successful `DELETE` with an empty `204`.
    func testSuccessfulAlarmDeletion() async throws {
        let alarm = try Fixtures.loadAlarm()
        XCTAssertNotNil(alarm)

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: 204) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarm.url.absoluteString) &&
            request.httpMethod == "DELETE"
        }

        let (_, response) = try await obacoService.deleteAlarm(url: alarm.url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse, "Expected deleteAlarm response to be of type HTTPURLResponse")
        XCTAssertEqual(httpResponse.statusCode, 204)
    }

    /// Sidecars predating the switch to `204` answer a successful `DELETE` with an empty
    /// `200`. `APIService.data(for:)` reads an empty-bodied `200` as a disguised 404 — a
    /// workaround for the REST API's handling of bogus IDs — which turned every successful
    /// alarm cancel into a `requestNotFound` failure. That heuristic must not apply here.
    func testSuccessfulAlarmDeletionWithEmpty200() async throws {
        let alarm = try Fixtures.loadAlarm()

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: 200) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarm.url.absoluteString) &&
            request.httpMethod == "DELETE"
        }

        let (_, response) = try await obacoService.deleteAlarm(url: alarm.url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse, "Expected deleteAlarm response to be of type HTTPURLResponse")
        XCTAssertEqual(httpResponse.statusCode, 200)
    }

    /// A genuine 404 — the alarm is already gone — must still surface as `requestNotFound`.
    func testAlarmDeletionWith404() async throws {
        let alarm = try Fixtures.loadAlarm()

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: 404) { (request) -> Bool in
            request.url!.absoluteString.starts(with: alarm.url.absoluteString) &&
            request.httpMethod == "DELETE"
        }

        do {
            _ = try await obacoService.deleteAlarm(url: alarm.url)
            XCTFail("Expected deleteAlarm to throw APIError.requestNotFound")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                XCTFail("Expected APIError.requestNotFound, got \(error)")
                return
            }
        }
    }
}
