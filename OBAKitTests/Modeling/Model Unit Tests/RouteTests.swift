//
//  RouteTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class RouteTests: OBATestCase {
    
    @Test func `Decode valid route`() {
        let routeData: [String: Any] = [
            "id": "1_100002",
            "agencyId": "1",
            "shortName": "ST Express",
            "longName": "Bellevue TC - Northgate TC via Fremont Ave N",
            "description": "Express route serving Bellevue and Northgate",
            "type": 3,
            "url": "https://www.soundtransit.org/schedules/st-express-594",
            "color": "00953a",
            "textColor": "ffffff"
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        
        #expect(route.id == "1_100002")
        #expect(route.agencyID == "1")
        #expect(route.shortName == "ST Express")
        #expect(route.longName == "Bellevue TC - Northgate TC via Fremont Ave N")
        #expect(route.routeDescription == "Express route serving Bellevue and Northgate")
        #expect(route.routeType == .bus)
        #expect(route.routeURL?.absoluteString == "https://www.soundtransit.org/schedules/st-express-594")
        #expect(route.color != nil)
        #expect(route.textColor != nil)
        #expect(route.agency == nil)
        #expect(route.regionIdentifier == nil)
    }
    
    @Test func `Decode minimal route`() {
        let minimalData: [String: Any] = [
            "id": "minimal_route",
            "agencyId": "2",
            "shortName": "99",
            "type": 3
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: minimalData)
        
        #expect(route.id == "minimal_route")
        #expect(route.agencyID == "2")
        #expect(route.shortName == "99")
        #expect(route.routeType == .bus)
        #expect(route.longName == nil)
        #expect(route.routeDescription == nil)
        #expect(route.color == nil)
        #expect(route.textColor == nil)
        #expect(route.routeURL == nil)
    }
    
    @Test func `Decode with blank values`() {
        let dataWithBlanks: [String: Any] = [
            "id": "blank_route",
            "agencyId": "3",
            "shortName": "Empty Fields Route",
            "type": 3,
            "longName": "",
            "description": "",
            "color": "",
            "textColor": ""
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: dataWithBlanks)
        
        // String.nilifyBlankValue should convert empty strings to nil
        #expect(route.longName == nil)
        #expect(route.routeDescription == nil)
        #expect(route.color == nil)
        #expect(route.textColor == nil)
    }
    
    @Test func `Route type decoding`() {
        let testCases: [(Int, Route.RouteType)] = [
            (0, .lightRail),
            (1, .subway),
            (2, .rail),
            (3, .bus),
            (4, .ferry),
            (5, .cableCar),
            (6, .gondola),
            (7, .funicular),
            (999, .unknown),
            (12345, .unknown)
        ]
        
        for (rawValue, expectedType) in testCases {
            let data: [String: Any] = [
                "id": "test_route_\(rawValue)",
                "agencyId": "test_agency",
                "shortName": "Test",
                "type": rawValue
            ]
            
            let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: data)
            #expect(route.routeType == expectedType)
        }
    }
    
    @Test func `Has references load references`() {
        let routeData: [String: Any] = [
            "id": "1_100002",
            "agencyId": "1",
            "shortName": "Test Route",
            "type": 3
        ]
        
        let route = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        
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
            ]]
        ]
        
        let references = try! Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        
        route.loadReferences(references, regionIdentifier: 123)
        
        #expect(route.agency != nil)
        #expect(route.agency.id == "1")
        #expect(route.regionIdentifier == 123)
    }
    
    @Test func `Equality and hash`() {
        let routeData: [String: Any] = [
            "id": "equality_test",
            "agencyId": "1",
            "shortName": "Test Route",
            "type": 3
        ]
        
        let route1 = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        let route2 = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        
        let differentData: [String: Any] = [
            "id": "different_route",
            "agencyId": "2",
            "shortName": "Different Route",
            "type": 3
        ]
        
        let route3 = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: differentData)
        
        #expect(route1.isEqual(route2) == true)
        #expect(route1.isEqual(route3) == false)
        #expect(route1.isEqual("not a route") == false)
        
        #expect(route1.hash == route2.hash)
        #expect(route1.hash != route3.hash)
    }
    
    @Test func `Encode decode round trip`() {
        let routeData: [String: Any] = [
            "id": "roundtrip_test",
            "agencyId": "1",
            "shortName": "Test Route",
            "longName": "Long Test Route Name",
            "description": "A test route",
            "type": 3,
            "url": "https://example.com"
        ]
        
        let originalRoute = try! Fixtures.dictionaryToModel(type: Route.self, dictionary: routeData)
        let roundTrippedRoute = try! Fixtures.roundtripCodable(type: Route.self, model: originalRoute)
        
        #expect(roundTrippedRoute.id == originalRoute.id)
        #expect(roundTrippedRoute.agencyID == originalRoute.agencyID)
        #expect(roundTrippedRoute.shortName == originalRoute.shortName)
        #expect(roundTrippedRoute.longName == originalRoute.longName)
        #expect(roundTrippedRoute.routeDescription == originalRoute.routeDescription)
        #expect(roundTrippedRoute.routeType == originalRoute.routeType)
        #expect(roundTrippedRoute.routeURL == originalRoute.routeURL)
    }
    
    @Test func `Array extension sort`() {
        let route1Data: [String: Any] = ["id": "route1", "agencyId": "1", "shortName": "z Route", "type": 3]
        let route2Data: [String: Any] = ["id": "route2", "agencyId": "1", "shortName": "A Route", "type": 3]
        let route3Data: [String: Any] = ["id": "route3", "agencyId": "1", "shortName": "m Route", "type": 3]
        
        let routes = try! [
            Fixtures.dictionaryToModel(type: Route.self, dictionary: route1Data),
            Fixtures.dictionaryToModel(type: Route.self, dictionary: route2Data),
            Fixtures.dictionaryToModel(type: Route.self, dictionary: route3Data)
        ]
        
        let sortedRoutes = routes.localizedCaseInsensitiveSort()
        
        #expect(sortedRoutes[0].shortName == "A Route")
        #expect(sortedRoutes[1].shortName == "m Route")
        #expect(sortedRoutes[2].shortName == "z Route")
    }

    @Test func `Array extension sort numeric`() {
        let routeNames = ["10", "3", "11", "49", "Bellevue", "12"]
        let routes = try! routeNames.enumerated().map { (index, name) -> Route in
            let dict: [String: Any] = ["id": "route_\(index)", "agencyId": "1", "shortName": name, "type": 3]
            return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
        }

        let sortedRoutes = routes.localizedCaseInsensitiveSort()
        let sortedNames = sortedRoutes.map(\.shortName)

        #expect(sortedNames == ["3", "10", "11", "12", "49", "Bellevue"])
    }
}

// MARK: - Frequency Tests

@Suite(.serialized)
final class FrequencyTests: OBATestCase {
    
    @Test func `Decode valid frequency`() {
        let frequencyData: [String: Any] = [
            "startTime": 1609459200000, // Milliseconds since epoch
            "endTime": 1609545600000,   
            "headway": 600.0         // 10 minutes
        ]
        
        let frequency = try! Fixtures.dictionaryToModel(type: Frequency.self, dictionary: frequencyData)
        
        #expect(frequency.startTime.timeIntervalSince1970 == 1610437507200)
        #expect(frequency.endTime.timeIntervalSince1970 == 1610523907200)
        #expect(frequency.headway == 600.0)
    }
    
    @Test func `Frequency equality`() {
        let frequencyData: [String: Any] = [
            "startTime": 1609459200000,
            "endTime": 1609545600000,
            "headway": 600.0
        ]
        
        let frequency1 = try! Fixtures.dictionaryToModel(type: Frequency.self, dictionary: frequencyData)
        let frequency2 = try! Fixtures.dictionaryToModel(type: Frequency.self, dictionary: frequencyData)
        
        var differentData = frequencyData
        differentData["headway"] = 300.0
        let frequency3 = try! Fixtures.dictionaryToModel(type: Frequency.self, dictionary: differentData)
        
        #expect(frequency1.isEqual(frequency2) == true)
        #expect(frequency1.isEqual(frequency3) == false)
        #expect(frequency1.hash == frequency2.hash)
        #expect(frequency1.hash != frequency3.hash)
    }
    
    @Test func `Decode failure when missing required fields`() {
        let incompleteData: [String: Any] = [
            "endTime": 1609545600000,
            "headway": 600.0
        ]
        // Missing startTime
        
        #expect(throws: (any Error).self) {
            try Fixtures.dictionaryToModel(type: Frequency.self, dictionary: incompleteData)
        }
    }
}
