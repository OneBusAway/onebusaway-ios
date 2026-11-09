//
//  DonationRequestModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `DonationRequest` model JSON decoding, encoding, equality, and hash consistency.
///
/// Verifies round-trip Codable compliance, value equivalence across identical payloads,
/// and property isolation across distinct donation campaign identifiers.
@Suite(.serialized)
struct DonationRequestModelTests {

    private func makeJSON(
        id: String = "donation_campaign_2026",
        headline: String = "Support Open Transit",
        body: String = "OneBusAway is made possible by riders like you.",
        actionButtonText: String = "Donate Now"
    ) throws -> Data {
        let dict: [String: Any] = [
            "id": id,
            "headline": headline,
            "body": body,
            "actionButtonText": actionButtonText
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Decoding and Properties

    @Test func `DonationRequest decodes expected fields from JSON payload`() throws {
        let data = try makeJSON()
        let request = try JSONDecoder().decode(DonationRequest.self, from: data)

        #expect(request.id == "donation_campaign_2026")
        #expect(request.headline == "Support Open Transit")
        #expect(request.body == "OneBusAway is made possible by riders like you.")
        #expect(request.actionButtonText == "Donate Now")
    }

    @Test func `DonationRequest decoding fails when required keys are missing`() throws {
        let incomplete: [String: Any] = [
            "id": "partial_campaign",
            "headline": "Incomplete Data"
            // Missing body and actionButtonText
        ]
        let data = try JSONSerialization.data(withJSONObject: incomplete)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DonationRequest.self, from: data)
        }
    }

    // MARK: - Codable Round-Tripping

    @Test func `DonationRequest preserves all properties through Codable round-trip`() throws {
        let original = DonationRequest(
            id: "roundtrip_test",
            headline: "Keep Transit Free",
            body: "Your contribution keeps real-time data running 24/7.",
            actionButtonText: "Contribute $5"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DonationRequest.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.headline == original.headline)
        #expect(decoded.body == original.body)
        #expect(decoded.actionButtonText == original.actionButtonText)
    }

    // MARK: - Equality and Hash Consistency

    @Test func `DonationRequest equality and hash consistency across identical values`() {
        let req1 = DonationRequest(id: "camp_1", headline: "H1", body: "B1", actionButtonText: "A1")
        let req2 = DonationRequest(id: "camp_1", headline: "H1", body: "B1", actionButtonText: "A1")
        let req3 = DonationRequest(id: "camp_2", headline: "H1", body: "B1", actionButtonText: "A1")
        let req4 = DonationRequest(id: "camp_1", headline: "H2", body: "B1", actionButtonText: "A1")

        #expect(req1 == req2)
        #expect(req1.hashValue == req2.hashValue)
        #expect(req1 != req3)
        #expect(req1 != req4)
    }

    @Test func `DonationRequest operates correctly in Set and Dictionary keys`() {
        let req1 = DonationRequest(id: "c1", headline: "H", body: "B", actionButtonText: "A")
        let req2 = DonationRequest(id: "c2", headline: "H", body: "B", actionButtonText: "A")

        let set: Set<DonationRequest> = [req1, req2, req1]
        #expect(set.count == 2)
        #expect(set.contains(req1))
        #expect(set.contains(req2))

        let dict: [DonationRequest: String] = [req1: "Val1", req2: "Val2"]
        #expect(dict[req1] == "Val1")
        #expect(dict[req2] == "Val2")
    }
}
