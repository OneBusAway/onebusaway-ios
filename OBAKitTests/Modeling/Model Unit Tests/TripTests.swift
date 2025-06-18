//
//  TripTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class TripTests: OBATestCase {
    
    func test_decodeValidTrip() {
        let tripData: [String: Any] = [
            "id": "1_18196913",
            "blockId": "7001_1001",
            "routeId": "1_100002",
            "serviceId": "1_20200101",
            "shapeId": "1_20010002",
            "tripHeadsign": "Bellevue TC",
            "tripShortName": "Express 001",
            "direction": "0",
            "routeShortName": "ST Express",
            "timeZone": "America/Los_Angeles"
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        
        expect(trip.id) == "1_18196913"
        expect(trip.blockID) == "7001_1001"
        expect(trip.routeID) == "1_100002"
        expect(trip.serviceID) == "1_20200101"
        expect(trip.shapeID) == "1_20010002"
        expect(trip.headsign) == "Bellevue TC"
        expect(trip.shortName) == "Express 001"
        expect(trip.direction) == "0"
        expect(trip.routeShortName) == "ST Express"
        expect(trip.timeZone) == "America/Los_Angeles"
        expect(trip.route).to(beNil())
        expect(trip.regionIdentifier).to(beNil())
    }
    
    func test_decodeMinimalTrip() {
        let minimalData: [String: Any] = [
            "id": "minimal_trip",
            "blockId": "block_123",
            "routeId": "route_456",
            "serviceId": "service_789",
            "shapeId": "shape_abc",
            "routeShortName": "99",
            "tripShortName": "Short",
            "timeZone": "UTC"
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: minimalData)
        
        expect(trip.id) == "minimal_trip"
        expect(trip.blockID) == "block_123"
        expect(trip.routeID) == "route_456"
        expect(trip.serviceID) == "service_789"
        expect(trip.shapeID) == "shape_abc"
        expect(trip.routeShortName) == "99"
        expect(trip.shortName) == "Short"
        expect(trip.timeZone) == "UTC"
    }
    
    func test_decodeWithBlankValues() {
        let dataWithBlanks: [String: Any] = [
            "id": "blank_trip",
            "blockId": "block_blank",
            "routeId": "route_blank",
            "serviceId": "service_blank",
            "shapeId": "shape_blank",
            "routeShortName": "",
            "tripShortName": "",
            "timeZone": ""
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: dataWithBlanks)
        
        // String.nilifyBlankValue should convert empty strings to nil
        expect(trip.routeShortName).to(beNil())
        expect(trip.shortName).to(beNil())
        expect(trip.timeZone).to(beNil())
    }
    
    func test_hasReferencesLoadReferences() {
        let tripData: [String: Any] = [
            "id": "test_trip",
            "blockId": "test_block",
            "routeId": "1_100002",
            "serviceId": "test_service",
            "shapeId": "test_shape",
            "routeShortName": "Test",
            "tripShortName": "Test",
            "timeZone": "UTC"
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        
        
        // Create References from JSON data since it only has Decodable initializer
        let referencesData: [String: Any] = [
            "agencies": [[
                "id": "1",
                "name": "Test Agency",
                "url": "https://example.com",
                "timezone": "UTC",
                "lang": "en",
                "phone": "555-0123",
                "privateService": false
            ]],
            "routes": [[
                "id": "1_100002",
                "agencyId": "1",
                "shortName": "ST Express",
                "type": 3
            ]]
        ]
        
        let references = try! Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        
        trip.loadReferences(references, regionIdentifier: 456)
        
        expect(trip.route).toNot(beNil())
        expect(trip.route.id) == "1_100002"
        expect(trip.regionIdentifier) == 456
    }
    
    func test_routeHeadsign() {
        let tripData: [String: Any] = [
            "id": "headsign_trip",
            "blockId": "test_block",
            "routeId": "1_100002",
            "serviceId": "test_service",
            "shapeId": "test_shape",
            "tripHeadsign": "Bellevue TC",
            "routeShortName": "ST Express",
            "tripShortName": "Test",
            "timeZone": "UTC"
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        
        let routeData: [String: Any] = [
            "id": "1_100002",
            "agencyId": "1",
            "shortName": "ST Express",
            "type": 3
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        trip.route = route
        
        expect(trip.routeHeadsign) == "ST Express - Bellevue TC"
    }
    
    func test_routeHeadsignWithoutTripHeadsign() {
        let tripData: [String: Any] = [
            "id": "no_headsign_trip",
            "blockId": "test_block",
            "routeId": "1_100002",
            "serviceId": "test_service",
            "shapeId": "test_shape",
            "routeShortName": "ST Express",
            "tripShortName": "Test",
            "timeZone": "UTC"
        ]
        
        let trip = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        
        let routeData: [String: Any] = [
            "id": "1_100002",
            "agencyId": "1",
            "shortName": "ST Express",
            "type": 3
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        trip.route = route
        
        expect(trip.routeHeadsign) == "ST Express"
    }
    
    func test_equalityAndHash() {
        let tripData: [String: Any] = [
            "id": "equality_test",
            "blockId": "test_block",
            "routeId": "test_route",
            "serviceId": "test_service",
            "shapeId": "test_shape",
            "routeShortName": "Test",
            "tripShortName": "Test",
            "timeZone": "UTC"
        ]
        
        let trip1 = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        let trip2 = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: tripData)
        
        let differentData = tripData.merging(["id": "different_trip"]) { _, new in new }
        let trip3 = try! Fixtures.dictionaryToModel(type: Trip.self, dictionary: differentData)
        
        expect(trip1.isEqual(trip2)) == true
        expect(trip1.isEqual(trip3)) == false
        expect(trip1.isEqual("not a trip")) == false
        
        expect(trip1.hash) == trip2.hash
        expect(trip1.hash) != trip3.hash
    }
}
