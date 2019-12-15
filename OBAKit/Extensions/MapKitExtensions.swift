//
//  MapKit.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

// MARK: - MKDirections

extension MKDirections {
    /// Creates a directions object that will calculate walking directions from the user's current location to the specified destination.
    ///
    /// - Parameter coordinate: The destination coordinate
    /// - Returns: A directions object
    public class func walkingDirections(to coordinate: CLLocationCoordinate2D) -> MKDirections {
        let walkingRequest = MKDirections.Request()
        walkingRequest.source = MKMapItem.forCurrentLocation()
        walkingRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        walkingRequest.transportType = .walking
        return MKDirections(request: walkingRequest)
    }
}

// MARK: - MKMapRect

extension MKMapRect {
    /// Converts the `MKMapRect` into an array of `MKMapPoint`s for rendering as an overlay.
    var mapPoints: [MKMapPoint] {
        [
            MKMapPoint(x: minX, y: minY),
            MKMapPoint(x: minX, y: maxY),
            MKMapPoint(x: maxX, y: maxY),
            MKMapPoint(x: maxX, y: minY)
        ]
    }

    /// Creates an `MKPolygon` from the receiver.
    var polygon: MKPolygon {
        var points = [MKMapPoint]()
        points.append(contentsOf: mapPoints)
        return MKPolygon(points: points, count: points.count)
    }
}

public extension MKMapRect {
    init(_ coordinateRegion: MKCoordinateRegion) {
        let topLeft = CLLocationCoordinate2D(
            latitude: coordinateRegion.center.latitude + (coordinateRegion.span.latitudeDelta/2.0),
            longitude: coordinateRegion.center.longitude - (coordinateRegion.span.longitudeDelta/2.0)
        )

        let bottomRight = CLLocationCoordinate2D(
            latitude: coordinateRegion.center.latitude - (coordinateRegion.span.latitudeDelta/2.0),
            longitude: coordinateRegion.center.longitude + (coordinateRegion.span.longitudeDelta/2.0)
        )

        let topLeftMapPoint = MKMapPoint(topLeft)
        let bottomRightMapPoint = MKMapPoint(bottomRight)

        let origin = MKMapPoint(x: topLeftMapPoint.x,
                                y: topLeftMapPoint.y)
        let size = MKMapSize(width: fabs(bottomRightMapPoint.x - topLeftMapPoint.x),
                             height: fabs(bottomRightMapPoint.y - topLeftMapPoint.y))

        self.init(origin: origin, size: size)
    }
}

// MARK: - MKMapRect/Codable

extension MKMapRect: Codable {
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        origin = try container.decode(MKMapPoint.self, forKey: .origin)
        size = try container.decode(MKMapSize.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(size, forKey: .size)
    }

    private enum CodingKeys: String, CodingKey {
        case origin, size
    }
}

// MARK: - MKMapPoint

extension MKMapPoint: Codable {
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }
}

// MARK: - MKMapSize

extension MKMapSize: Codable {
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    private enum CodingKeys: String, CodingKey {
        case width, height
    }
}

// MARK: - MKMapView

//  Based on http://troybrant.net/blog/2010/01/set-the-zoom-level-of-an-mkmapview/
//  https://gist.github.com/PowerPan/ab6de0fc246d29ec2372ec954c4d966d
public extension MKMapView {
    func setCenterCoordinate(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Int, animated: Bool = true) {
        // clamp large numbers to 28
        let zoomL = min(zoomLevel, 28)

        // use the zoom level to compute the region
        let span = MapHelpers.coordinateSpanFrom(size: bounds.size, centerCoordinate: centerCoordinate, zoomLevel: zoomL)
        let region = MKCoordinateRegion(center: centerCoordinate, span: span)

        setRegion(region, animated: animated)
    }
}

extension MKMapView {

    /// Syntactic sugar for registering annotation views
    ///
    /// - Parameter type: The type that is being registered.
    func registerAnnotationView<T>(_ type: T.Type) where T: MKAnnotationView {
        register(type, forAnnotationViewWithReuseIdentifier: MKMapView.reuseIdentifier(for: type))
    }

    /// Standardized method for generating map view reuse identifiers.
    ///
    /// - Parameter type: The type for which a reuse identifier is desired.
    /// - Returns: The reuse identifier.
    class func reuseIdentifier<T>(for type: T.Type) -> String where T: MKAnnotationView {
        return String(describing: type)
    }

    /// Replaces already-installed overlays of the specified type with the new overlays provided.
    ///
    /// - Parameters:
    ///   - newOverlays: The new overlays of the specified type that will appear on the map.
    ///   - level: The overlay level at which new overlays will be added.
    func updateOverlays<T>(with newOverlays: [T], level: MKOverlayLevel) where T: MKOverlay & Hashable {
        let oldOverlays: Set<T> = Set(overlays.filter(type: T.self))
        let newOverlays: Set<T> = Set(newOverlays)

        // Which elements are in both sets?
        let overlap = newOverlays.intersection(oldOverlays)

        // Which elements have been completely removed?
        let removed = oldOverlays.subtracting(overlap)

        // Which elements are completely new?
        let added = newOverlays.subtracting(overlap)

        removeOverlays(removed.allObjects)
        addOverlays(added.allObjects, level: level)
    }

    /// Replaces already-installed annotations of the specified type with the new annotations provided.
    ///
    /// - Parameters:
    ///   - newAnnotations: The new annotations of the specified type that will appear on the map.
    func updateAnnotations<T>(with newAnnotations: [T]) where T: MKAnnotation & Hashable {
        let oldAnnotations: Set<T> = Set(annotations.filter(type: T.self))
        let newAnnotations: Set<T> = Set(newAnnotations)

        // Which elements are in both sets?
        let overlap = newAnnotations.intersection(oldAnnotations)

        // Which elements have been completely removed?
        let removed = oldAnnotations.subtracting(overlap)

        // Which elements are completely new?
        let added = newAnnotations.subtracting(overlap)

        removeAnnotations(removed.allObjects)
        addAnnotations(added.allObjects)
    }

    /// Removes all annotations from the map view, with the possible exception of the user's location annotation if available.
    /// - Parameter excludeUserLocation: Set this to `true` to keep the user location annotation visible on the map.
    func removeAllAnnotations(excludeUserLocation: Bool = true) {
        let allAnnotations = excludeUserLocation ? annotations : annotations.filter { !($0 is MKUserLocation) }
        removeAnnotations(allAnnotations)
    }

    /// Removes all `MKAnnotation`s of a particular type `T` from the map.
    /// For instance, you can remove all `Stop` annotations from the map.
    /// - Parameter type: The kind of annotation to remove from the map.
    func removeAnnotations<T>(type: T.Type) where T: MKAnnotation & Hashable {
        let annotationsOfType = annotations.filter { $0 is T }
        removeAnnotations(annotationsOfType)
    }
}

// MARK: - MKPolygon

extension MKPolygon {
    convenience init(coordinateRegion: MKCoordinateRegion) {
        var points = [CLLocationCoordinate2D]()

        let sw = CLLocationCoordinate2D(latitude: coordinateRegion.center.latitude - (coordinateRegion.span.latitudeDelta / 2.0), longitude: coordinateRegion.center.longitude - (coordinateRegion.span.longitudeDelta / 2.0))
        points.append(sw)

        let nw = CLLocationCoordinate2D(latitude: coordinateRegion.center.latitude + (coordinateRegion.span.latitudeDelta / 2.0), longitude: coordinateRegion.center.longitude - (coordinateRegion.span.longitudeDelta / 2.0))
        points.append(nw)

        let ne = CLLocationCoordinate2D(latitude: coordinateRegion.center.latitude + (coordinateRegion.span.latitudeDelta / 2.0), longitude: coordinateRegion.center.longitude + (coordinateRegion.span.longitudeDelta / 2.0))
        points.append(ne)

        let se = CLLocationCoordinate2D(latitude: coordinateRegion.center.latitude - (coordinateRegion.span.latitudeDelta / 2.0), longitude: coordinateRegion.center.longitude + (coordinateRegion.span.longitudeDelta / 2.0))
        points.append(se)

        self.init(coordinates: points, count: 4)
    }
}

// MARK: - MKUserLocation

extension MKUserLocation {

    /// Returns `false` if `location` is `nil` or equal to `(0,0)`, and `true` otherwise.
    public var isValid: Bool {
        guard let location = location else { return false }
        return location.coordinate.latitude != 0 && location.coordinate.longitude != 0
    }
}
