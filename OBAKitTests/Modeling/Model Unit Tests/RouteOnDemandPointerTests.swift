//
//  RouteOnDemandPointerTests.swift
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
final class RouteOnDemandPointerTests: OBATestCase {

    @Test func `Route with an on-demand pointer decodes it`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_with_ondemand_pointer.json")).entry
        #expect(route.id == "CC_CC3")
        #expect(route.onDemandServiceIDs == ["CC_CC3"])
    }

    @Test func `Legacy route decodes an empty pointer list and omits it when encoding`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_1_10.json")).entry
        #expect(route.onDemandServiceIDs.isEmpty)
        let encoded = try JSONEncoder.RESTEncoder().encode(route)
        let keys = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys
        #expect(!keys.contains("onDemandServiceIds"))
    }

    @Test func `Route pointer round-trips`() throws {
        let route = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Route>.self, from: Fixtures.loadData(file: "route_with_ondemand_pointer.json")).entry
        let copy = try Fixtures.roundtripCodable(type: Route.self, model: route)
        #expect(copy.onDemandServiceIDs == ["CC_CC3"])
        #expect(copy == route)
    }

    @Test func `Reference routes inside an on-demand response carry the pointer`() throws {
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<OnDemandService>.self, from: Fixtures.loadData(file: "ondemand_service_alexandria.json"))
        #expect(response.entry.route?.onDemandServiceIDs == ["5088_77652"])
    }
}
