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
            "requirement": "certificationRequired"
        ]

        let eligibility = try Fixtures.dictionaryToModel(type: OnDemandEligibility.self, dictionary: json)

        #expect(eligibility.requirement == .certificationRequired)
        #expect(eligibility.infoURL == nil)
    }

    @Test func `Decode OnDemandEligibility with unknown requirement falls back gracefully`() throws {
        let json: [String: Any] = [
            "requirement": "some_future_unsupported_requirement",
            "infoUrl": "" // Empty string should nilify via String.nilifyBlankValue
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

    // MARK: - ServiceKind Enum Decoding

    @Test func `ServiceKind enum decoding known cases`() throws {
        let kinds: [String: ServiceKind] = [
            "zone": .zone,
            "zoneToZone": .zoneToZone,
            "stopGroup": .stopGroup,
            "deviatedRoute": .deviatedRoute,
            "unknown": .unknown
        ]

        for (raw, expected) in kinds {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(ServiceKind.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test func `ServiceKind falls back to unknown for unrecognized server strings`() throws {
        let forwardCompatibleStrings = [
            "\"pointToPoint\"",
            "\"autonomousShuttle\"",
            "\"futureMode\"",
            "\"\""
        ]

        for jsonString in forwardCompatibleStrings {
            let data = Data(jsonString.utf8)
            let decoded = try JSONDecoder().decode(ServiceKind.self, from: data)
            #expect(decoded == .unknown)
        }
    }

    // MARK: - MatchReason Enum Decoding

    @Test func `MatchReason enum decoding known cases`() throws {
        let reasons: [String: MatchReason] = [
            "areaContainsPoint": .areaContainsPoint,
            "stopWithinRadius": .stopWithinRadius,
            "areaNearby": .areaNearby,
            "areaIntersectsViewport": .areaIntersectsViewport,
            "stopWithinViewport": .stopWithinViewport,
            "unknown": .unknown
        ]

        for (raw, expected) in reasons {
            let data = Data("\"\(raw)\"".utf8)
            let decoded = try JSONDecoder().decode(MatchReason.self, from: data)
            #expect(decoded == expected)
        }
    }

    @Test func `MatchReason falls back to unknown for unexpected reasons`() throws {
        let unexpected = [
            "\"corridorBuffer\"",
            "\"routeProjection\"",
            "\"randomNewReason\""
        ]

        for jsonString in unexpected {
            let data = Data(jsonString.utf8)
            let decoded = try JSONDecoder().decode(MatchReason.self, from: data)
            #expect(decoded == .unknown)
        }
    }

    // MARK: - OnDemandGeometryDetail

    @Test func `OnDemandGeometryDetail string raw values and initialization`() {
        #expect(OnDemandGeometryDetail.none.rawValue == "none")
        #expect(OnDemandGeometryDetail.simplified.rawValue == "simplified")
        #expect(OnDemandGeometryDetail.full.rawValue == "full")

        #expect(OnDemandGeometryDetail(rawValue: "none") == .none)
        #expect(OnDemandGeometryDetail(rawValue: "simplified") == .simplified)
        #expect(OnDemandGeometryDetail(rawValue: "full") == .full)
        #expect(OnDemandGeometryDetail(rawValue: "unknown") == nil)
        #expect(OnDemandGeometryDetail(rawValue: "") == nil)
    }
}
