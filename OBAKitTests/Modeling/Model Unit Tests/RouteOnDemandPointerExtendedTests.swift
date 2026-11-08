//
//  RouteOnDemandPointerExtendedTests.swift
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

/// Tests for `Route.onDemandServiceIDs` pointer parsing across diverse payload structures,
/// empty list omission in JSON serialization, and equality discrimination.
@Suite(.serialized)
final class RouteOnDemandPointerExtendedTests: OBATestCase {

    private func makeRouteJSON(
        id: String = "route_1",
        onDemandIDs: [String]? = nil
    ) -> Data {
        var dict: [String: Any] = [
            "id": id,
            "agencyId": "1",
            "shortName": "44",
            "type": 3
        ]
        if let onDemandIDs {
            dict["onDemandServiceIds"] = onDemandIDs
        }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - On-Demand Pointer Decoding

    @Test func `Route decodes multiple onDemandServiceIDs when provided in payload`() throws {
        let data = makeRouteJSON(id: "r_multi", onDemandIDs: ["flex_zone_1", "flex_zone_2"])
        let route = try JSONDecoder.RESTDecoder().decode(Route.self, from: data)

        #expect(route.id == "r_multi")
        #expect(route.onDemandServiceIDs == ["flex_zone_1", "flex_zone_2"])
    }

    @Test func `Route decodes empty onDemandServiceIDs array when key is absent`() throws {
        let data = makeRouteJSON(id: "r_standard", onDemandIDs: nil)
        let route = try JSONDecoder.RESTDecoder().decode(Route.self, from: data)

        #expect(route.id == "r_standard")
        #expect(route.onDemandServiceIDs.isEmpty)
    }

    // MARK: - Key Omission during Encoding

    @Test func `Encoding Route without pointers omits onDemandServiceIds key to preserve cache blob compatibility`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(Route.self, from: makeRouteJSON(id: "r_plain", onDemandIDs: nil))
        let encoded = try JSONEncoder.RESTEncoder().encode(route)

        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(!json.keys.contains("onDemandServiceIds"))
    }

    @Test func `Encoding Route with pointers includes onDemandServiceIds key`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(Route.self, from: makeRouteJSON(id: "r_flex", onDemandIDs: ["ondemand_1"]))
        let encoded = try JSONEncoder.RESTEncoder().encode(route)

        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(json.keys.contains("onDemandServiceIds"))
        #expect(json["onDemandServiceIds"] as? [String] == ["ondemand_1"])
    }
}
