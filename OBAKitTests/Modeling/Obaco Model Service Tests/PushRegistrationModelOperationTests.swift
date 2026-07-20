//
//  PushRegistrationModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

/// Tests for the OBACloud `push_registrations` API (issue #1204): registering the
/// device's APNs token so agencies can push service alerts to opted-in riders.
class PushRegistrationModelOperationTests: OBATestCase {

    /// Captures the body of the request the service actually put on the wire. Single
    /// request per test, written before the mock returns and read after the `await`
    /// resumes, so there's no concurrent access in practice.
    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var body: String?
        nonisolated(unsafe) var url: URL?
    }

    private func mockRegistrationPOST(statusCode: Int = 204) -> RequestCapture {
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            guard request.httpMethod == "POST", request.url?.path.hasSuffix("/push_registrations") ?? false else {
                return false
            }
            capture.body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            capture.url = request.url
            return true
        }
        return capture
    }

    func testSuccessfulRegistration_sendsAllContractParams() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "es-MX", testDevice: false, description: nil)

        let body = try XCTUnwrap(capture.body, "Expected postPushRegistration to send a form-encoded body")
        XCTAssertTrue(body.contains("token=01abff007f"), "Body: \(body)")
        XCTAssertTrue(body.contains("operating_system=ios"), "Body: \(body)")
        XCTAssertTrue(body.contains("locale=es-MX"), "Body: \(body)")
        // The server upserts on every call and an omitted test_device resets the stored
        // value to false — the param's *presence* on every request is contract, not just
        // its value.
        XCTAssertTrue(body.contains("test_device=false"), "Body: \(body)")
    }

    func testRegistration_flagsTestDevices() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: true, description: "Aarons iPhone")

        let body = try XCTUnwrap(capture.body)
        XCTAssertTrue(body.contains("test_device=true"), "Body: \(body)")
        // NetworkHelpers.dictionary(toHTTPBodyData:) percent-encodes the space as %20 —
        // CharacterSet.urlQueryAllowed doesn't include space.
        XCTAssertTrue(body.contains("description=Aarons%20iPhone"), "Body: \(body)")
    }

    func testRegistration_flagsApnsSandboxInDebugBuilds() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: true, description: "Aarons iPhone")

        let body = try XCTUnwrap(capture.body)
        XCTAssertTrue(body.contains("apns_sandbox=1"), "Expected a debug build to flag its registration for the APNs sandbox — its token is only valid there, so an unflagged test push bounces with BadDeviceToken. Body: \(body)")
    }

    /// A blank/omitted description must never reach the wire — the server treats an empty
    /// `description` param the same as a missing one, and `test_device=false` doesn't
    /// require one at all.
    func testRegistration_omitsBlankDescription() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: false, description: nil)

        let body = try XCTUnwrap(capture.body)
        XCTAssertFalse(body.contains("description="), "Body: \(body)")
    }

    func testRegistration_targetsRegionScopedURL() async throws {
        let capture = mockRegistrationPOST()

        try await obacoService.postPushRegistration(token: "01abff007f", locale: "en-US", testDevice: false, description: nil)

        let url = try XCTUnwrap(capture.url)
        XCTAssertTrue(
            url.absoluteString.starts(with: "https://alerts.example.com/api/v2/regions/1/push_registrations"),
            "URL: \(url.absoluteString)")
    }

    /// The server answers validation failures with a 422 — that must surface as an error.
    func testRegistrationValidationFailureThrows() async throws {
        _ = mockRegistrationPOST(statusCode: 422)

        do {
            try await obacoService.postPushRegistration(token: "", locale: "en-US", testDevice: false, description: nil)
            XCTFail("Expected postPushRegistration to throw APIError.requestFailure")
        } catch let error as APIError {
            guard case .requestFailure = error else {
                XCTFail("Expected APIError.requestFailure, got \(error)")
                return
            }
        }
    }

    /// Mocks the `DELETE /push_registrations` response for the token used by the
    /// unregistration tests.
    private func mockUnregistrationDELETE(statusCode: Int) {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        dataLoader.mock(data: Data(), statusCode: statusCode) { request in
            request.httpMethod == "DELETE" &&
            (request.url?.path.hasSuffix("/push_registrations") ?? false) &&
            (request.url?.query?.contains("token=01abff007f") ?? false)
        }
    }

    func testSuccessfulUnregistration() async throws {
        mockUnregistrationDELETE(statusCode: 204)

        let (_, response) = try await obacoService.deletePushRegistration(token: "01abff007f")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 204)
    }

    /// A 404 means the token was never registered — safe for callers to ignore, but the
    /// service layer still surfaces it faithfully.
    func testUnregistrationWith404Throws() async throws {
        mockUnregistrationDELETE(statusCode: 404)

        do {
            _ = try await obacoService.deletePushRegistration(token: "01abff007f")
            XCTFail("Expected deletePushRegistration to throw APIError.requestNotFound")
        } catch let error as APIError {
            guard case .requestNotFound = error else {
                XCTFail("Expected APIError.requestNotFound, got \(error)")
                return
            }
        }
    }
}
