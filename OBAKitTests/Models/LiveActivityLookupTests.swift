//
//  LiveActivityLookupTests.swift
//  OBAKitTests
//
//  Copyright (c) Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

struct LiveActivityLookupTests {
    
    @Test func tracksSameTripWithIdenticalData() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        
        #expect(staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksDifferentTripWithDifferentStopID() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_101", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        
        #expect(!staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksDifferentTripWithDifferentRoute() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "11", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        
        #expect(!staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksDifferentTripWithDifferentHeadsign() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Uptown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        
        #expect(!staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksDifferentTripWithDifferentTripID() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_2")
        
        #expect(!staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksSameTripWithEmptyTripIDWildcardOnLhs() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        
        #expect(staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksSameTripWithEmptyTripIDWildcardOnRhs() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: nil, regionID: 1, tripID: "")
        
        #expect(staticData1.tracksSameTrip(as: staticData2))
    }
    
    @Test func tracksSameTripWithDifferingRouteColorAndRegionID() {
        let staticData1 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: "FF0000", regionID: 1, tripID: "trip_1")
        let staticData2 = TripAttributes.StaticData(routeShortName: "10", routeHeadsign: "Downtown", stopID: "1_100", routeColorHex: "00FF00", regionID: 2, tripID: "trip_1")
        
        #expect(staticData1.tracksSameTrip(as: staticData2))
    }
}
