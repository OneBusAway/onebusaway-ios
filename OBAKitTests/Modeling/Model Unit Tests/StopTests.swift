//
//  StopTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class StopTests: OBATestCase {

    @Test func `Roundtripping stops`() {
        let stopOne = try! Fixtures.loadSomeStops().first!
        let data = try! PropertyListEncoder().encode(stopOne)
        let stopTwo = try! PropertyListDecoder().decode(Stop.self, from: data)

        // `routes` is `[Route]!`, populated by reference-reconnection rather than
        // by decoding, so these two are real nil checks -- not the tautologies
        // that the other `!= nil` assertions in this test were.
        #expect(stopTwo.routes != nil)

        #expect(stopOne.routeIDs.count == 12)
        #expect(stopOne.routes != nil)
        #expect(stopOne.routes.count == 12)

        #expect(stopOne == stopTwo)
        #expect(stopOne.routes == stopTwo.routes)
    }

    @Test func `Stop with an on-demand pointer decodes it`() throws {
        let data = Fixtures.loadData(file: "stop_with_ondemand_pointer.json")
        let stop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: data).entry
        #expect(stop.id == "CC_CC_Ironton_Ferry_West")
        #expect(stop.onDemandServiceIDs == ["CC_CC3"])
    }

    @Test func `Stop without the key decodes an empty pointer list`() throws {
        let flexServerStop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: Fixtures.loadData(file: "stop_alexandria_4258639.json")).entry
        #expect(flexServerStop.onDemandServiceIDs.isEmpty)

        let legacyStop = try Fixtures.loadSomeStops().first!
        #expect(legacyStop.onDemandServiceIDs.isEmpty)
    }

    @Test func `Pointer round-trips and is omitted when empty`() throws {
        let data = Fixtures.loadData(file: "stop_with_ondemand_pointer.json")
        let stop = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: data).entry
        let copy = try Fixtures.roundtripCodable(type: Stop.self, model: stop)
        #expect(copy.onDemandServiceIDs == ["CC_CC3"])
        #expect(copy == stop)

        let legacy = try Fixtures.loadSomeStops().first!
        let encoded = try JSONEncoder.RESTEncoder().encode(legacy)
        let keys = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys
        #expect(!keys.contains("onDemandServiceIds"), "cached blobs must stay byte-identical for non-flex stops")
    }

    @Test func `Pointer participates in equality`() throws {
        let withPointer = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: Fixtures.loadData(file: "stop_with_ondemand_pointer.json")).entry
        let json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "stop_with_ondemand_pointer.json")) as! [String: Any]
        var dataDict = json["data"] as! [String: Any]
        var entry = dataDict["entry"] as! [String: Any]
        entry.removeValue(forKey: "onDemandServiceIds")
        dataDict["entry"] = entry
        var stripped = json
        stripped["data"] = dataDict
        let withoutPointer = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<Stop>.self, from: JSONSerialization.data(withJSONObject: stripped)).entry
        #expect(withPointer != withoutPointer)
        #expect(withPointer.hash != withoutPointer.hash)
    }
}
