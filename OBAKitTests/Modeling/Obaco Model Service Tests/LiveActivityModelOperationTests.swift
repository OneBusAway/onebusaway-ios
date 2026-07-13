//
//  LiveActivityModelOperationTests.swift
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

class LiveActivityModelOperationTests: OBATestCase {

    func testSuccessfulLiveActivityRegistration() async throws {
        let data = """
        {"url": "https://sidecar.onebusaway.org/api/v2/regions/1/live_activities/abc123"}
        """.data(using: .utf8)!

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)

        var capturedRequest: URLRequest?
        dataLoader.mock(data: data) { request in
            capturedRequest = request
            return request.url?.host == "alerts.example.com" &&
                request.url?.path == "/api/v2/regions/1/live_activities" &&
                request.httpMethod == "POST"
        }

        let url = try await obacoService.postLiveActivity(
            activityID: "activity-123",
            pushToken: "push-token-abc",
            stopID: "1_11420",
            routeShortName: "10",
            tripHeadsign: "Downtown Seattle",
            tripID: nil,
            serviceDate: nil,
            vehicleID: nil,
            stopSequence: nil
        )

        XCTAssertEqual(url.absoluteString, "https://sidecar.onebusaway.org/api/v2/regions/1/live_activities/abc123")

        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        let params = formParams(from: bodyString)

        XCTAssertEqual(params["activity_id"], "activity-123")
        XCTAssertEqual(params["push_token"], "push-token-abc")
        XCTAssertEqual(params["stop_id"], "1_11420")
        XCTAssertEqual(params["route_short_name"], "10")
        XCTAssertEqual(params["trip_headsign"], "Downtown Seattle")
        XCTAssertNil(params["trip_id"])
        XCTAssertNil(params["service_date"])
        XCTAssertNil(params["vehicle_id"])
        XCTAssertNil(params["stop_sequence"])
        XCTAssertEqual(params["apns_sandbox"], "1", "Expected a debug build to flag the Live Activity for the APNs sandbox, as the ActivityKit token is a sandbox token. Without this flag, server routes pushes to production APNs and they bounce.")
    }

    func testSuccessfulLiveActivityDeletion() async throws {
        let liveActivityURL = URL(string: "https://sidecar.onebusaway.org/api/v2/regions/1/live_activities/abc123")!

        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data()) { (request) -> Bool in
            request.url!.absoluteString.starts(with: liveActivityURL.absoluteString) &&
            request.httpMethod == "DELETE"
        }

        let (_, response) = try await obacoService.deleteLiveActivity(url: liveActivityURL)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse, "Expected deleteLiveActivity response to be of type HTTPURLResponse")
        XCTAssertEqual(httpResponse.statusCode, 200)
    }

    // MARK: - Helpers

    /// Parses an `application/x-www-form-urlencoded` request body (as produced by
    /// `NetworkHelpers.dictionary(toHTTPBodyData:)`) into a `[String: String]` for
    /// per-key assertions, since dictionary key order isn't guaranteed.
    private func formParams(from body: String) -> [String: String] {
        var result = [String: String]()
        for pair in body.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            result[key] = value
        }
        return result
    }
}
