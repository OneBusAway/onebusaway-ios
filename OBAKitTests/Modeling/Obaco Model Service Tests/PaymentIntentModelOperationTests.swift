//
//  PaymentIntentModelOperationTests.swift
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

// swiftlint:disable force_cast

/// Tests for the Obaco `postCreatePaymentIntent` endpoint and `PaymentIntentResponse` model.
@Suite(.serialized)
final class PaymentIntentModelOperationTests: OBATestCase {

    private final class RequestCapture: @unchecked Sendable {
        nonisolated(unsafe) var method: String?
        nonisolated(unsafe) var url: URL?
        nonisolated(unsafe) var jsonBody: [String: Any]?
    }

    private let sampleResponseJSON = """
    {
        "id": "pi_3MtwBwLkdIwHu7ix28a3tqPa",
        "client_secret": "pi_3MtwBwLkdIwHu7ix28a3tqPa_secret_Yrjf984",
        "customer_id": "cus_NffrFeUfNV2Hib",
        "ephemeral_key": "ek_test_YWNjdF8xMDMyODJY"
    }
    """

    private let minimalResponseJSON = """
    {
        "id": "pi_minimal_12345",
        "client_secret": "pi_secret_minimal"
    }
    """

    private func mockPaymentIntentPOST(responseJSON: String, statusCode: Int = 200) -> RequestCapture {
        let capture = RequestCapture()
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let data = Data(responseJSON.utf8)

        dataLoader.mock(data: data, statusCode: statusCode) { request in
            guard request.httpMethod == "POST",
                  request.url?.path == "/api/v1/payment_intents" else {
                return false
            }
            capture.method = request.httpMethod
            capture.url = request.url
            if let bodyData = request.httpBody {
                capture.jsonBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
            return true
        }
        return capture
    }

    // MARK: - Successful POST and Payload Validation

    @Test func `Successful payment intent creation sends expected JSON payload and decodes all fields`() async throws {
        let capture = mockPaymentIntentPOST(responseJSON: sampleResponseJSON)

        let response = try await obacoService.postCreatePaymentIntent(
            donationAmountInCents: 2500,
            recurring: true,
            name: "Jane Transit",
            email: "jane@example.com",
            testMode: false
        )

        // Verify request payload on wire
        #expect(capture.method == "POST")
        let json = try #require(capture.jsonBody, "Expected postCreatePaymentIntent to send JSON body")
        #expect(json["donation_amount_in_cents"] as? Int == 2500)
        #expect(json["donation_frequency"] as? String == "recurring")
        #expect(json["name"] as? String == "Jane Transit")
        #expect(json["email"] as? String == "jane@example.com")
        #expect(json["test_mode"] as? String == "0")

        // Verify decoded model
        #expect(response.id == "pi_3MtwBwLkdIwHu7ix28a3tqPa")
        #expect(response.clientSecret == "pi_3MtwBwLkdIwHu7ix28a3tqPa_secret_Yrjf984")
        #expect(response.customerID == "cus_NffrFeUfNV2Hib")
        #expect(response.ephemeralKey == "ek_test_YWNjdF8xMDMyODJY")
    }

    @Test func `One-time donation and testMode flag set correct wire values`() async throws {
        let capture = mockPaymentIntentPOST(responseJSON: minimalResponseJSON)

        let response = try await obacoService.postCreatePaymentIntent(
            donationAmountInCents: 500,
            recurring: false,
            name: "Test Rider",
            email: "rider@test.org",
            testMode: true
        )

        let json = try #require(capture.jsonBody)
        #expect(json["donation_amount_in_cents"] as? Int == 500)
        #expect(json["donation_frequency"] as? String == "onetime")
        #expect(json["test_mode"] as? String == "1")

        // Verify minimal response decoding (nil optional fields)
        #expect(response.id == "pi_minimal_12345")
        #expect(response.clientSecret == "pi_secret_minimal")
        #expect(response.customerID == nil)
        #expect(response.ephemeralKey == nil)
    }

    // MARK: - Model Equatable & Identifiable

    @Test func `PaymentIntentResponse equality and hash consistency`() {
        let response1 = PaymentIntentResponse(
            clientSecret: "secret_1",
            customerID: "cus_1",
            ephemeralKey: "ek_1",
            id: "pi_1"
        )
        let response2 = PaymentIntentResponse(
            clientSecret: "secret_1",
            customerID: "cus_1",
            ephemeralKey: "ek_1",
            id: "pi_1"
        )
        let response3 = PaymentIntentResponse(
            clientSecret: "secret_diff",
            customerID: "cus_1",
            ephemeralKey: "ek_1",
            id: "pi_1"
        )

        #expect(response1 == response2)
        #expect(response1 != response3)
        #expect(response1.hashValue == response2.hashValue)
        #expect(response1.id == "pi_1")
    }

    // MARK: - Server Error Handling

    @Test func `postCreatePaymentIntent handles 400 Bad Request error`() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://alerts.example.com/api/v1/payment_intents")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let mockResponse = MockDataResponse(
            data: Data("{\"error\": \"invalid_amount\"}".utf8),
            urlResponse: urlResponse,
            error: nil
        ) { request in
            request.httpMethod == "POST" && request.url?.path == "/api/v1/payment_intents"
        }
        dataLoader.mock(response: mockResponse)

        let thrown = await #expect(throws: APIError.self) {
            _ = try await obacoService.postCreatePaymentIntent(
                donationAmountInCents: -100,
                recurring: false,
                name: "Invalid",
                email: "invalid@example.com",
                testMode: false
            )
        }

        guard case .requestFailure(let response)? = thrown, response.statusCode == 400 else {
            Issue.record("Expected APIError.requestFailure with 400, got \(String(describing: thrown))")
            return
        }
    }

    @Test func `postCreatePaymentIntent handles 500 server error`() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let urlResponse = HTTPURLResponse(
            url: URL(string: "https://alerts.example.com/api/v1/payment_intents")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        let mockResponse = MockDataResponse(
            data: Data("Internal Server Error".utf8),
            urlResponse: urlResponse,
            error: nil
        ) { request in
            request.httpMethod == "POST" && request.url?.path == "/api/v1/payment_intents"
        }
        dataLoader.mock(response: mockResponse)

        let thrown = await #expect(throws: APIError.self) {
            _ = try await obacoService.postCreatePaymentIntent(
                donationAmountInCents: 1000,
                recurring: false,
                name: "User",
                email: "user@example.com",
                testMode: false
            )
        }

        guard case .requestFailure(let response)? = thrown, response.statusCode == 500 else {
            Issue.record("Expected APIError.requestFailure with 500, got \(String(describing: thrown))")
            return
        }
    }
}
