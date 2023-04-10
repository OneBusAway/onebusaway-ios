//
//  Geohash+MapKit.swift
//
//  Created by Alan Chu on 8/2/20.
//

#if canImport(MapKit)
import MapKit

extension Geohash {
    /// The geohash cell expressed as an `MKCoordinateRegion`.
    public var region: MKCoordinateRegion {
        let coordinates = CLLocationCoordinate2D(latitude: self.latitude, longitude: self.longitude)
        let size = self.size

        let span = MKCoordinateSpan(latitudeDelta: size.latitude,
                                    longitudeDelta: size.longitude)

        return MKCoordinateRegion(center: coordinates, span: span)
    }
}
#endif

#if canImport(CoreLocation)
import CoreLocation

extension Geohash {
    /// Creates a geohash based on the provided coordinates and the requested precision.
    /// - parameter coordinates: The coordinates to use for generating the hash.
    /// - parameter precision: The number of characters to generate.
    ///     ```
    ///     Precision   Cell width      Cell height
    ///             1   ≤ 5,000km   x   5,000km
    ///             2   ≤ 1,250km   x   625km
    ///             3   ≤ 156km     x   156km
    ///             4   ≤ 39.1km    x   19.5km
    ///             5   ≤ 4.89km    x   4.89km
    ///             6   ≤ 1.22km    x   0.61km
    ///             7   ≤ 153m      x   153m
    ///             8   ≤ 38.2m     x   19.1m
    ///             9   ≤ 4.77m     x   4.77m
    ///            10   ≤ 1.19m     x   0.596m
    ///            11   ≤ 149mm     x   149mm
    ///            12   ≤ 37.2mm    x   18.6mm
    ///     ```
    /// - returns: If the specified coordinates are invalid, this returns nil.
    public init?(_ coordinates: CLLocationCoordinate2D, precision: Int) {
        self.init(coordinates: (coordinates.latitude, coordinates.longitude), precision: precision)
    }
}
#endif
