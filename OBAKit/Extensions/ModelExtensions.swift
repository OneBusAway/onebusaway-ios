//
//  ModelExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/8/19.
//

import Foundation
import MapKit
import OBAKitCore

// MARK: - Region/MKAnnotation

extension Region: MKAnnotation {
    public var coordinate: CLLocationCoordinate2D {
        centerCoordinate
    }

    public var title: String? {
        name
    }
}

// MARK: - Stop/MKAnnotation

/// Adds conformance to `MKAnnotation` to `Stop`.
/// Includes additional methods for rendering extra data directly onto the map.
///
/// - Note: See `StopAnnotationView`for more details.
extension Stop: MKAnnotation {
    public var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }

    public var title: String? {
        return Formatters.formattedTitle(stop: self)
    }

    public var subtitle: String? {
        return Formatters.formattedRoutes(routes)
    }

    public var mapTitle: String? {
        return routes.map { $0.shortName }.localizedCaseInsensitiveSort().prefix(3).joined(separator: ", ")
    }

    public var mapSubtitle: String? {
        return Formatters.adjectiveFormOfCardinalDirection(direction)
    }
}

// MARK: - TripStatus/MKAnnotation

/// Adds conformance to `MKAnnotation` to `TripStatus`.
/// Includes additional methods for rendering extra data directly onto the map.
extension TripStatus: MKAnnotation {

    public var coordinate: CLLocationCoordinate2D {
        lastKnownLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    public var title: String? {
        activeTrip.routeShortName
    }
}
