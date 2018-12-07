//
//  StopOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 12/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopOperation: RESTAPIOperation {
    private static let apiPath = "/api/where/stop/%@.json"

    public class func buildAPIPath(stopID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(stopID))
    }

    public class func buildURL(stopID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return _buildURL(fromBaseURL: baseURL, path: buildAPIPath(stopID: stopID), queryItems: queryItems)
    }
}
