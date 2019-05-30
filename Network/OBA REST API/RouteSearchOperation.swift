//
//  RouteSearchOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/8/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

// swiftlint:disable opening_brace

@objc(OBARouteSearchOperation)
public class RouteSearchOperation: RESTAPIOperation {
    public private(set) var outOfRange = false

    override public func dataFieldsDidSet() {
        if  let decodedJSONBody = decodedJSONBody as? [AnyHashable: Any],
            let outOfRange = decodedJSONBody["outOfRange"] as? Bool
        {
            self.outOfRange = outOfRange
        }
    }

    public static let apiPath = "/api/where/routes-for-location.json"

    /*
     See https://github.com/OneBusAway/onebusaway-iphone/issues/601
     for more information on this. In short, the issue is that
     the route disambiguation UI should always appears when there are
     multiple routes whose names contain the same search string, but
     sometimes this doesn't happen. It's a result of routes-for-location
     searches not having a wide enough radius.
     */
    private static let regionalRadius: CLLocationDistance = 40000.0

    public class func buildURL(searchQuery: String, region: CLCircularRegion, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        let radius = max(region.radius, regionalRadius)
        let args: [String: Any] = [
            "lat": region.center.latitude,
            "lon": region.center.longitude,
            "query": searchQuery,
            "radius": String(radius)
        ]

        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: NetworkHelpers.dictionary(toQueryItems: args) + defaultQueryItems)
    }
}
