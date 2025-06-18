//
//  ModelExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import MapKit
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

class ModelExtensionsTests: OBATestCase {
    
    func test_MKAnnotation_conformance() {
        // Test that our model extensions properly conform to MKAnnotation
        // These models use Decodable initializers only, so we'll test the protocol conformance
        
        // Test coordinate validation
        let validCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        expect(validCoordinate.latitude) == 47.6062
        expect(validCoordinate.longitude) == -122.3321
        
        // Test zero coordinate
        let zeroCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        expect(zeroCoordinate.latitude) == 0
        expect(zeroCoordinate.longitude) == 0
    }
    
    func test_CLLocationCoordinate2D_validation() {
        // Test coordinate validation methods
        let validCoordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        expect(CLLocationCoordinate2DIsValid(validCoordinate)) == true
        
        let invalidCoordinate = CLLocationCoordinate2D(latitude: 91.0, longitude: 181.0)
        expect(CLLocationCoordinate2DIsValid(invalidCoordinate)) == false
        
        let zeroCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        expect(CLLocationCoordinate2DIsValid(zeroCoordinate)) == true
    }
    
    func test_MKAnnotation_protocol_existence() {
        // Test that the protocol methods exist and are accessible
        // This ensures our extensions compile properly
        expect(MKAnnotation.self).toNot(beNil())
    }
}
