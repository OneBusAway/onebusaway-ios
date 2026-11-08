//
//  OnDemandDomainModelTests.swift
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

@Suite(.serialized)
final class OnDemandDomainModelTests {

    // MARK: - OnDemandEligibility

    @Test func `Decode OnDemandEligibility with open requirement and info URL`() throws {
        let json: [String: Any] = [
            "requirement": "open",
            "infoUrl": "https://transit.example.com/eligibility"
        ]

        let eligibility = try Fixtures.dictionaryToModel(type: OnDemandEligibility.self, dictionary: json)

        #expect(eligibility.requirement == .open)
        #expect(eligibility.infoURL?.absoluteString == "https://transit.example.com/eligibility")
    }

    @Test func `Decode OnDemandEligibility with certificationRequired requirement`() throws {
        let json: [String: Any] = [
            "requirement": "certification_required"
        ]

        let eligibility = try Fixtures.dictionaryToModel(type: OnDemandEligibility.self, dictionary: json)

        #expect(eligibility.requirement == .certificationRequired)
        #expect(eligibility.infoURL == nil)
    }

    @Test func `Decode OnDemandEligibility with unknown requirement falls back gracefully`() throws {
        let json: [String: Any] = [
            "requirement": "some_future_unsupported_requirement",
            "infoUrl": "   " // Blank whitespace string should nilify
        ]

        let eligibility = try Fixtures.dictionaryToModel(type: OnDemandEligibility.self, dictionary: json)

        #expect(eligibility.requirement == .unknown)
        #expect(eligibility.infoURL == nil)
    }

    @Test func `OnDemandEligibility memberwise initializer equality and hashing`() {
        let url = URL(string: "https://example.com")!
        let e1 = OnDemandEligibility(requirement: .open, infoURL: url)
        let e2 = OnDemandEligibility(requirement: .open, infoURL: url)
        let e3 = OnDemandEligibility(requirement: .certificationRequired, infoURL: nil)

        #expect(e1 == e2)
        #expect(e1.hashValue == e2.hashValue)
        #expect(e1 != e3)
    }

    // MARK: - ServiceKind Enum Decoding & Fallback

    @Test func `ServiceKind enum decoding known cases`() throws {
        let kinds: [String: ServiceKind] = [
            "zone": .zone,
            "zoneToZone": .zoneToZone,
            "stopGroup": .stopGroup,
            "deviatedRoute": .deviatedRoute
        ]

        for (raw, expected) in kinds {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(ServiceKind.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test func `ServiceKind enum decoding unknown fallback`() throws {
        let data = Data("\"future_kind\"".utf8)
        let decoded = try JSONDecoder().decode(ServiceKind.self, from: data)
        #expect(decoded == .unknown)
    }

    // MARK: - MatchReason Enum Decoding & Fallback

    @Test func `MatchReason enum decoding known cases`() throws {
        let reasons: [String: MatchReason] = [
            "areaContainsPoint": .areaContainsPoint,
            "stopWithinRadius": .stopWithinRadius,
            "areaNearby": .areaNearby,
            "areaIntersectsViewport": .areaIntersectsViewport,
            "stopWithinViewport": .stopWithinViewport
        ]

        for (raw, expected) in reasons {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(MatchReason.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test func `MatchReason enum decoding unknown fallback`() throws {
        let data = Data("\"new_server_reason\"".utf8)
        let decoded = try JSONDecoder().decode(MatchReason.self, from: data)
        #expect(decoded == .unknown)
    }

    // MARK: - OnDemandGeometryDetail

    @Test func `OnDemandGeometryDetail string raw values`() {
        #expect(OnDemandGeometryDetail.none.rawValue == "none")
        #expect(OnDemandGeometryDetail.simplified.rawValue == "simplified")
        #expect(OnDemandGeometryDetail.full.rawValue == "full")
    }
}
