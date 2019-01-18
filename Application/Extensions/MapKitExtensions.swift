//
//  MapKit.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

// MARK: - Directions

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

// MARK: - Map View

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

    /// Replaces already-installed annotations of the specified type with the new annotations provided.
    ///
    /// - Parameters:
    ///   - newAnnotations: The new annotations of the specified type that will appear on the map.
    func updateAnnotations<T>(with newAnnotations: [T]) where T: MKAnnotation, T: Hashable {
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
}

public extension MKMapRect {
    public init(_ coordinateRegion: MKCoordinateRegion) {
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
