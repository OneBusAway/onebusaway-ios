//
//  AppInterop.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Creates the URLs necessary to deep link into other apps.
public class AppInterop: NSObject {

    /// Creates an URL that can open the Google Maps app with the user's desired
    /// destination in walking directions mode.
    ///
    /// - Parameter coordinate: The destination coordinate
    /// - Returns: An URL that will launch Google Maps in walking directions mode
    public class func googleMapsWalkingDirectionsURL(coordinate: CLLocationCoordinate2D) -> URL? {
        var params: [URLQueryItem] = []
        params.append(URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"))
        params.append(URLQueryItem(name: "directionsmode", value: "walking"))

        guard let components = NSURLComponents(string: "comgooglemaps://") else {
            return nil
        }

        components.queryItems = params
        return components.url
    }

    /// Creates an URL that can open the Apple Maps app with the user's desired
    /// destination in walking directions mode.
    ///
    /// - Parameter coordinate: The destination coordinate
    /// - Returns: An URL that will launch Apple Maps in walking directions mode
    public class func appleMapsWalkingDirectionsURL(coordinate: CLLocationCoordinate2D) -> URL? {
        var params: [URLQueryItem] = []
        params.append(URLQueryItem.init(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"))
        params.append(URLQueryItem.init(name: "dirflg", value: "w"))

        guard let components = NSURLComponents(string: "http://maps.apple.com/") else {
            return nil
        }

        components.queryItems = params

        return components.url
    }

    /// Creates a URL that can open OpenStreetMap in a web browser with the user's desired
    /// destination in walking directions mode.
    ///
    /// - Parameter coordinate: The destination coordinate
    /// - Returns: An URL that will launch OpenStreetMap in walking directions mode
    public class func openStreetMapWalkingDirectionsURL(coordinate: CLLocationCoordinate2D) -> URL? {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        var components = URLComponents(string: "https://www.openstreetmap.org/directions")
        components?.queryItems = [
            URLQueryItem(name: "engine", value: "osrm_foot"),
            URLQueryItem(name: "from", value: ""),
            URLQueryItem(name: "to", value: "\(lat),\(lon)")
        ]
        components?.fragment = "map=16/\(lat)/\(lon)"
        return components?.url
    }
}
