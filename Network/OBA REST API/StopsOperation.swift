//
//  StopsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/4/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

public class StopsOperation: RESTAPIOperation {

    public private(set) var outOfRange = false

    public override func _dataFieldsDidSet() {
        if  let decodedJSONBody = _decodedJSONBody as? [AnyHashable: Any],
            let outOfRange = decodedJSONBody["outOfRange"] as? Bool
        {
            self.outOfRange = outOfRange
        }
    }

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/stops-for-location.json"

    public class func buildURL(coordinate: CLLocationCoordinate2D, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let queryItems = NetworkHelpers.dictionary(toQueryItems: ["lat": coordinate.latitude, "lon": coordinate.longitude])
        return _buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems + defaultQueryItems)
    }

    public class func buildURL(region: MKCoordinateRegion, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let queryItems = NetworkHelpers.dictionary(toQueryItems: [
            "lat": region.center.latitude, "lon": region.center.longitude,
            "latSpan": region.span.latitudeDelta, "lonSpan": region.span.longitudeDelta
        ])
        return _buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems + defaultQueryItems)
    }

    public class func buildURL(circularRegion: CLCircularRegion, query: String, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        // make sure radius is greater than zero and less than 15000
        let radius = max(min(15000.0, circularRegion.radius), 1.0)
        let queryItems = NetworkHelpers.dictionary(toQueryItems: [
            "lat": circularRegion.center.latitude, "lon": circularRegion.center.longitude,
            "query": query, "radius": radius
        ])
        return _buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems + defaultQueryItems)
    }
}
