//
//  StopsOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

public typealias GetStopsCompletion = (_ operation: StopsOperation) -> Void

public class StopsOperation: WrappedResponseNetworkOperation {

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/stops-for-location.json"

    public class func buildURL(coordinate: CLLocationCoordinate2D, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let queryItems = NetworkHelpers.dictionary(toQueryItems: ["lat": coordinate.latitude, "lon": coordinate.longitude])
        return buildURL(baseURL: baseURL, queryItems: queryItems + defaultQueryItems)
    }

    public class func buildURL(region: MKCoordinateRegion, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let queryItems = NetworkHelpers.dictionary(toQueryItems: [
            "lat": region.center.latitude, "lon": region.center.longitude,
            "latSpan": region.span.latitudeDelta, "lonSpan": region.span.longitudeDelta
        ])
        return buildURL(baseURL: baseURL, queryItems: queryItems + defaultQueryItems)
    }

    public class func buildURL(circularRegion: CLCircularRegion, query: String, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let radius = max(15000.0, circularRegion.radius)
        let queryItems = NetworkHelpers.dictionary(toQueryItems: [
            "lat": circularRegion.center.latitude, "lon": circularRegion.center.longitude,
            "query": query, "radius": radius
        ])
        return buildURL(baseURL: baseURL, queryItems: queryItems + defaultQueryItems)
    }

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = apiPath
        components.queryItems = queryItems
        return components.url!
    }
}
