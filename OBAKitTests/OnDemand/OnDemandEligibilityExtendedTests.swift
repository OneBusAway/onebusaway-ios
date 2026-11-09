//
//  OnDemandEligibilityExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `OnDemandEligibility` requirement parsing, unknown fallback,
/// URL decoding, and equality behavior.
@Suite(.serialized)
struct OnDemandEligibilityExtendedTests {

    // MARK: - Decoding

    @Test func `OnDemandEligibility decodes recognized requirements and valid infoURL`() throws {
        let json = """
        {
            "requirement": "certificationRequired",
            "infoUrl": "https://transit.example.com/eligibility"
        }
        """.data(using: .utf8)!

        let eligibility = try JSONDecoder().decode(OnDemandEligibility.self, from: json)
        #expect(eligibility.requirement == .certificationRequired)
        #expect(eligibility.infoURL == URL(string: "https://transit.example.com/eligibility"))
    }

    @Test func `OnDemandEligibility decodes open requirement without infoURL`() throws {
        let json = """
        {
            "requirement": "open"
        }
        """.data(using: .utf8)!

        let eligibility = try JSONDecoder().decode(OnDemandEligibility.self, from: json)
        #expect(eligibility.requirement == .open)
        #expect(eligibility.infoURL == nil)
    }

    @Test func `OnDemandEligibility degrades unrecognized requirement strings to unknown`() throws {
        let json = """
        {
            "requirement": "medicaidEnrolledOnly",
            "infoUrl": "https://transit.example.com/info"
        }
        """.data(using: .utf8)!

        let eligibility = try JSONDecoder().decode(OnDemandEligibility.self, from: json)
        #expect(eligibility.requirement == .unknown)
        #expect(eligibility.infoURL != nil)
    }

    @Test func `OnDemandEligibility treats blank or whitespace-only infoURL as nil`() throws {
        let json = """
        {
            "requirement": "open",
            "infoUrl": "   "
        }
        """.data(using: .utf8)!

        let eligibility = try JSONDecoder().decode(OnDemandEligibility.self, from: json)
        #expect(eligibility.requirement == .open)
        #expect(eligibility.infoURL == nil)
    }

    // MARK: - Hashable and Equatable

    @Test func `OnDemandEligibility equality across matching values`() {
        let url = URL(string: "https://example.com")!
        let e1 = OnDemandEligibility(requirement: .open, infoURL: url)
        let e2 = OnDemandEligibility(requirement: .open, infoURL: url)
        let eDiff = OnDemandEligibility(requirement: .certificationRequired, infoURL: url)

        #expect(e1 == e2)
        #expect(e1.hashValue == e2.hashValue)
        #expect(e1 != eDiff)
    }
}
