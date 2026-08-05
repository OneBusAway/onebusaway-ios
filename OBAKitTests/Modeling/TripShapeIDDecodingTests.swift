//
//  TripShapeIDDecodingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct TripShapeIDDecodingTests {

    private func decodeTrip(shapeIDFragment: String) throws -> Trip {
        let json = """
        {
          "blockId": "1_block", "id": "1_trip", "routeId": "1_100",
          "routeShortName": "40", "serviceId": "1_svc",
          \(shapeIDFragment)
          "tripShortName": "", "tripHeadsign": "Downtown Seattle",
          "timeZone": "America/Los_Angeles", "direction": "0"
        }
        """
        return try JSONDecoder().decode(Trip.self, from: Data(json.utf8))
    }

    @Test func `Present shapeId decodes`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": \"1_shape\",")
        #expect(trip.shapeID == "1_shape")
    }

    @Test func `Missing shapeId decodes to nil rather than throwing`() throws {
        let trip = try decodeTrip(shapeIDFragment: "")
        #expect(trip.shapeID == nil)
    }

    @Test func `Null shapeId decodes to nil`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": null,")
        #expect(trip.shapeID == nil)
    }

    @Test func `Blank shapeId is nilified like the adjacent string fields`() throws {
        let trip = try decodeTrip(shapeIDFragment: "\"shapeId\": \"\",")
        #expect(trip.shapeID == nil)
    }
}
