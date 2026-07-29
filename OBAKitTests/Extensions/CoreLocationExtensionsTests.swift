//
//  CoreLocationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit
import CoreGraphics
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class CoreLocationExtensionsTests {
    
    @Test func `CL authorization status description`() {
        #expect(CLAuthorizationStatus.authorizedAlways.description == "authorizedAlways")
        #expect(CLAuthorizationStatus.authorizedWhenInUse.description == "authorizedWhenInUse")
        #expect(CLAuthorizationStatus.denied.description == "denied")
        #expect(CLAuthorizationStatus.notDetermined.description == "notDetermined")
        #expect(CLAuthorizationStatus.restricted.description == "restricted")
    }
    
    @Test func `CL authorization status init from string`() {
        // LosslessStringConvertible init always returns nil as implemented
        #expect(CLAuthorizationStatus("authorizedAlways") == nil)
        #expect(CLAuthorizationStatus("denied") == nil)
        #expect(CLAuthorizationStatus("invalid") == nil)
    }
    
    @Test func `CL location direction radians`() {
        let direction: CLLocationDirection = 180.0 // 180 degrees
        let expectedRadians = Double.pi // π radians
        
        expectClose(direction.radians, expectedRadians, within: 0.0001)
        
        let direction90: CLLocationDirection = 90.0
        expectClose(direction90.radians, Double.pi / 2, within: 0.0001)
        
        let direction0: CLLocationDirection = 0.0
        expectClose(direction0.radians, 0.0, within: 0.0001)
    }
    
    @Test func `CL location direction affine transform`() {
        let direction: CLLocationDirection = 90.0 // 90 degrees
        let additionalRotation: CGFloat = CGFloat.pi / 4 // 45 degrees
        
        let transform = direction.affineTransform(rotatedBy: additionalRotation)
        
        #expect(type(of: transform) == CGAffineTransform.self)
        #expect(transform.isIdentity == false)
        
        // Test with zero additional rotation
        let transform0 = direction.affineTransform(rotatedBy: 0)
        #expect(type(of: transform0) == CGAffineTransform.self)
    }
    
    @Test func `CL location coordinate 2 d distance`() {
        let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let bellevue = CLLocationCoordinate2D(latitude: 47.6101, longitude: -122.2015)
        
        let distance = seattle.distance(from: bellevue)
        
        #expect(distance > 0)
        expectClose(distance, 10580, within: 1000) // Approximately 10.5km
        
        // Test distance to self
        let samePointDistance = seattle.distance(from: seattle)
        expectClose(samePointDistance, 0, within: 0.1)
    }
    
    @Test func `CL location coordinate 2 d is null island`() {
        let nullIsland = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        #expect(nullIsland.isNullIsland == true)
        
        let seattle = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        #expect(seattle.isNullIsland == false)
        
        let nearNullIsland = CLLocationCoordinate2D(latitude: 0.0001, longitude: 0.0)
        #expect(nearNullIsland.isNullIsland == false)
        
        let otherZero = CLLocationCoordinate2D(latitude: 0.0, longitude: -122.3321)
        #expect(otherZero.isNullIsland == false)
    }
    
    @Test func `CL circular region init with map rect`() {
        let mapRect = MKMapRect(
            x: 43013871.99811534,
            y: 93728205.2278356,
            width: 1984.0073646754026,
            height: 3397.6126077622175
        )
        
        let region = CLCircularRegion(mapRect: mapRect)
        
        #expect(region.identifier == "MapRectRegion")
        #expect(region.radius > 0)
        #expect(region.center.latitude != 0)
        #expect(region.center.longitude != 0)
        
        // Test with a simple square map rect
        let simpleRect = MKMapRect(x: 0, y: 0, width: 1000, height: 1000)
        let simpleRegion = CLCircularRegion(mapRect: simpleRect)
        
        #expect(simpleRegion.radius > 0)
        #expect(simpleRegion.identifier == "MapRectRegion")
    }
}
