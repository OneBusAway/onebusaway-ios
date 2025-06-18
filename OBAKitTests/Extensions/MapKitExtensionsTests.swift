//
//  MapKitExtensionsTests.swift
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

class MapKitExtensionsTests: XCTestCase {
    
    func test_MKDirections_walkingDirections() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let directions = MKDirections.walkingDirections(to: coordinate)
        
        // Test that we get a valid MKDirections object
        expect(directions).to(beAnInstanceOf(MKDirections.self))
        
        // We can't directly test the request properties since they're internal,
        // but we can verify the method creates a directions object successfully
        expect(directions).toNot(beNil())
    }
    
    func test_MKMapRect_mapPoints() {
        let mapRect = MKMapRect(x: 100, y: 200, width: 300, height: 400)
        let points = mapRect.mapPoints
        
        expect(points.count) == 4
        expect(points[0].x) == 100
        expect(points[0].y) == 200
        expect(points[1].x) == 100
        expect(points[1].y) == 600
        expect(points[2].x) == 400
        expect(points[2].y) == 600
        expect(points[3].x) == 400
        expect(points[3].y) == 200
    }
    
    func test_MKMapRect_polygon() {
        let mapRect = MKMapRect(x: 100, y: 200, width: 300, height: 400)
        let polygon = mapRect.polygon
        
        expect(polygon.pointCount) == 4
        expect(polygon).to(beAnInstanceOf(MKPolygon.self))
    }
    
    func test_MKMapRect_initFromCoordinateRegion() {
        let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: center, span: span)
        
        let mapRect = MKMapRect(region)
        
        expect(mapRect.size.width).to(beGreaterThan(0))
        expect(mapRect.size.height).to(beGreaterThan(0))
    }
    
    func test_MKMapRect_codable() throws {
        let originalRect = MKMapRect(x: 100, y: 200, width: 300, height: 400)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalRect)
        
        let decoder = JSONDecoder()
        let decodedRect = try decoder.decode(MKMapRect.self, from: data)
        
        expect(decodedRect.origin.x) == originalRect.origin.x
        expect(decodedRect.origin.y) == originalRect.origin.y
        expect(decodedRect.size.width) == originalRect.size.width
        expect(decodedRect.size.height) == originalRect.size.height
    }
    
    func test_MKMapPoint_codable() throws {
        let originalPoint = MKMapPoint(x: 123.45, y: 678.90)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalPoint)
        
        let decoder = JSONDecoder()
        let decodedPoint = try decoder.decode(MKMapPoint.self, from: data)
        
        expect(decodedPoint.x) == originalPoint.x
        expect(decodedPoint.y) == originalPoint.y
    }
    
    func test_MKMapSize_codable() throws {
        let originalSize = MKMapSize(width: 100.5, height: 200.75)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSize)
        
        let decoder = JSONDecoder()
        let decodedSize = try decoder.decode(MKMapSize.self, from: data)
        
        expect(decodedSize.width) == originalSize.width
        expect(decodedSize.height) == originalSize.height
    }
    
    func test_MKMapView_reuseIdentifier() {
        class TestAnnotationView: MKAnnotationView {}
        
        let identifier = MKMapView.reuseIdentifier(for: TestAnnotationView.self)
        expect(identifier) == "TestAnnotationView"
    }
    
    func test_MKPolygon_initFromCoordinateRegion() {
        let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: center, span: span)
        
        let polygon = MKPolygon(coordinateRegion: region)
        
        expect(polygon.pointCount) == 4
        expect(polygon).to(beAnInstanceOf(MKPolygon.self))
    }
    
    func test_MKUserLocation_isValid() {
        let userLocation = MKUserLocation()
        
        // Test with nil location
        expect(userLocation.isValid) == false
        
        // Test with zero coordinates
        let zeroLocation = CLLocation(latitude: 0, longitude: 0)
        userLocation.setValue(zeroLocation, forKey: "location")
        expect(userLocation.isValid) == false
        
        // Test with valid coordinates
        let validLocation = CLLocation(latitude: 47.6062, longitude: -122.3321)
        userLocation.setValue(validLocation, forKey: "location")
        expect(userLocation.isValid) == true
    }
}
