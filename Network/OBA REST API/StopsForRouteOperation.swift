//
//  StopsForRouteOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/7/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopsForRouteOperation: RESTAPIOperation {
    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/stops-for-route/%@.json"

    public class func buildAPIPath(routeID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(routeID))
    }

    public class func buildURL(routeID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return buildURL(fromBaseURL: baseURL, path: buildAPIPath(routeID: routeID), queryItems: queryItems)
    }
}
