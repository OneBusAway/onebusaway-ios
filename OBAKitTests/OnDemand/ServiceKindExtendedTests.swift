//
//  ServiceKindExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `ServiceKind` and `MatchReason` decoding resilience, raw value stability,
/// and fallback to `.unknown` for forward compatibility.
@Suite(.serialized)
struct ServiceKindExtendedTests {

    // MARK: - ServiceKind Decoding

    @Test func `ServiceKind decodes valid enum values`() throws {
        let cases: [(String, ServiceKind)] = [
            ("\"zone\"", .zone),
            ("\"zoneToZone\"", .zoneToZone),
            ("\"stopGroup\"", .stopGroup),
            ("\"deviatedRoute\"", .deviatedRoute),
            ("\"unknown\"", .unknown)
        ]

        for (jsonString, expected) in cases {
            let data = Data(jsonString.utf8)
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

    // MARK: - MatchReason Decoding

    @Test func `MatchReason decodes recognized location matching reasons`() throws {
        let cases: [(String, MatchReason)] = [
            ("\"areaContainsPoint\"", .areaContainsPoint),
            ("\"stopWithinRadius\"", .stopWithinRadius),
            ("\"areaNearby\"", .areaNearby),
            ("\"areaIntersectsViewport\"", .areaIntersectsViewport),
            ("\"stopWithinViewport\"", .stopWithinViewport),
            ("\"unknown\"", .unknown)
        ]

        for (jsonString, expected) in cases {
            let data = Data(jsonString.utf8)
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
}
