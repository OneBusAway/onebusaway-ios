//
//  StopTests.swift
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

    // MARK: - Direction Parsing & Canonical Abbreviations

    @Test func `Stop direction parsing and canonical abbreviations`() {
        let cases: [(String, Direction, String?)] = [
            ("N", .n, "N"),
            ("NE", .ne, "NE"),
            ("E", .e, "E"),
            ("SE", .se, "SE"),
            ("S", .s, "S"),
            ("SW", .sw, "SW"),
            ("W", .w, "W"),
            ("NW", .nw, "NW"),
            ("n", .n, "N"),
            ("sw", .sw, "SW"),
            ("UNKNOWN", .unknown, nil),
            ("invalid", .unknown, nil)
        ]
        for (raw, expectedDir, expectedAbbr) in cases {
            let stop = Stop(id: "stop_1", name: "Main St", direction: raw)
            #expect(stop.direction == expectedDir)
            #expect(stop.direction.canonicalAbbreviation == expectedAbbr)
        }
    }

    @Test func `Direction nil yields unknown direction`() {
        let stop = Stop(id: "stop_nil", name: "Main St", direction: nil)
        #expect(stop.direction == .unknown)
        #expect(stop.direction.canonicalAbbreviation == nil)
    }

    @Test func `Direction Comparable ordering`() {
        #expect(Direction.n < Direction.s)
        #expect(Direction.e < Direction.w)
        #expect(Direction.nw < Direction.unknown)
    }

    // MARK: - WheelchairBoarding Decoding

    @Test func `WheelchairBoarding decoding fallback`() throws {
        let cases: [(String, WheelchairBoarding)] = [
            ("accessible", .accessible),
            ("notAccessible", .notAccessible),
            ("unknown", .unknown),
            ("any_unrecognized_value", .unknown)
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\""
            let decoded = try JSONDecoder().decode(WheelchairBoarding.self, from: Data(json.utf8))
            #expect(decoded == expected)
        }
    }

    // MARK: - StopLocationType Decoding

    @Test func `StopLocationType decoding fallback`() throws {
        let cases: [(Int, StopLocationType)] = [
            (0, .stop),
            (1, .station),
            (2, .stationEntrance),
            (99, .unknown)
        ]
        for (raw, expected) in cases {
            let json = "\(raw)"
            let decoded = try JSONDecoder().decode(StopLocationType.self, from: Data(json.utf8))
            #expect(decoded == expected)
        }
    }

    // MARK: - Prioritized Route Type For Display

    @Test func `Prioritized route type selects ferry over bus`() {
        let stop = Stop(id: "stop_multi", name: "Colman Dock")
        let busRoute = Route(id: "route_bus", shortName: "Bus", routeType: .bus)
        let ferryRoute = Route(id: "route_ferry", shortName: "Ferry", routeType: .ferry)
        stop.routes = [busRoute, ferryRoute]

        #expect(stop.prioritizedRouteTypeForDisplay == .ferry)
    }

    @Test func `Prioritized route type selects light rail over bus`() {
        let stop = Stop(id: "stop_station", name: "Westlake")
        let busRoute = Route(id: "route_bus", shortName: "Bus", routeType: .bus)
        let lightRailRoute = Route(id: "route_light_rail", shortName: "1 Line", routeType: .lightRail)
        stop.routes = [busRoute, lightRailRoute]

        #expect(stop.prioritizedRouteTypeForDisplay == .lightRail)
    }

    @Test func `Prioritized route type falls back to unknown when no routes match hierarchy`() {
        let stop = Stop(id: "stop_empty", name: "Empty Stop")
        stop.routes = []
        #expect(stop.prioritizedRouteTypeForDisplay == .unknown)
    }

    // MARK: - Stop Equality and Hash

    @Test func `Stop equality compares core properties`() {
        let stop1 = Stop(id: "stop_a", name: "Broadway", code: "1001", direction: "N")
        let stop2 = Stop(id: "stop_a", name: "Broadway", code: "1001", direction: "N")
        let stopDiffName = Stop(id: "stop_a", name: "Broadway E", code: "1001", direction: "N")
        let stopDiffCode = Stop(id: "stop_a", name: "Broadway", code: "1002", direction: "N")

        #expect(stop1 == stop2)
        #expect(stop1.hashValue == stop2.hashValue)
        #expect(stop1 != stopDiffName)
        #expect(stop1 != stopDiffCode)
    }

    @Test func `Stop custom debug description includes id and name`() {
        let stop = Stop(id: "stop_debug", name: "Pine & 4th")
        #expect(stop.debugDescription.contains("stop_debug"))
        #expect(stop.debugDescription.contains("Pine & 4th"))
    }
}
