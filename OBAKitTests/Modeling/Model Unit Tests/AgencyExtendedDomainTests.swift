//
//  AgencyExtendedDomainTests.swift
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

/// Tests for `Agency` equality semantics, hash code consistency,
/// timezone parsing, contact information, and optional URL fields.
@Suite(.serialized)
final class AgencyExtendedDomainTests: OBATestCase {

    private func makeAgency(
        id: String,
        name: String = "Test Transit Agency",
        url: String = "https://agency.example.org",
        timezone: String = "America/Los_Angeles",
        lang: String = "en",
        phone: String = "206-555-0100",
        fareURL: String? = "https://agency.example.org/fares",
        email: String? = "support@agency.example.org",
        disclaimer: String? = "Test agency disclaimer",
        isPrivate: Bool = false
    ) throws -> Agency {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "url": url,
            "timezone": timezone,
            "lang": lang,
            "phone": phone,
            "privateService": isPrivate
        ]
        if let fareURL { dict["fareUrl"] = fareURL }
        if let email { dict["email"] = email }
        if let disclaimer { dict["disclaimer"] = disclaimer }

        return try Fixtures.dictionaryToModel(type: Agency.self, dictionary: dict)
    }

    // MARK: - Agency Identity and Equality

    @Test func `Agency equality uses object identity`() throws {
        let agency1 = try makeAgency(id: "agency_1", name: "Metro Transit")
        let agency2 = try makeAgency(id: "agency_1", name: "Metro Transit - Renamed")
        let agency3 = try makeAgency(id: "agency_2", name: "Sound Transit")

        #expect(agency1 == agency1)
        #expect(agency1 != agency2)
        #expect(agency1 != agency3)
    }

    // MARK: - TimeZone Parsing

    @Test func `Agency timezone parses into standard TimeZone instance`() throws {
        let pstAgency = try makeAgency(id: "a_pst", timezone: "America/Los_Angeles")
        #expect(pstAgency.resolvedTimeZone?.identifier == "America/Los_Angeles")

        let estAgency = try makeAgency(id: "a_est", timezone: "America/New_York")
        #expect(estAgency.resolvedTimeZone?.identifier == "America/New_York")
    }

    // MARK: - Optional Fields Handling

    @Test func `Agency handles presence and absence of optional URLs and contact info`() throws {
        let fullAgency = try makeAgency(
            id: "full",
            phone: "123-456-7890",
            fareURL: "https://fares.org",
            email: "info@fares.org",
            disclaimer: "Legal Notice",
            isPrivate: true
        )

        #expect(fullAgency.phone == "123-456-7890")
        #expect(fullAgency.fareURL == URL(string: "https://fares.org"))
        #expect(fullAgency.email == "info@fares.org")
        #expect(fullAgency.disclaimer == "Legal Notice")
        #expect(fullAgency.isPrivateService == true)

        let minimalAgency = try makeAgency(
            id: "minimal",
            phone: "555-0199",
            fareURL: nil,
            email: nil,
            disclaimer: nil,
            isPrivate: false
        )

        #expect(minimalAgency.fareURL == nil)
        #expect(minimalAgency.email == nil)
        #expect(minimalAgency.disclaimer == nil)
        #expect(minimalAgency.isPrivateService == false)
    }
}
