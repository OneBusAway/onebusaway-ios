//
//  CurrentTimeOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The operation for loading the `/api/where/current-time.json` endpoint.
public class CurrentTimeOperation: RESTAPIOperation {
    public var currentTime: Date? {
        guard
            let decodedBody = decodedJSONBody as? [String: Any],
            let currentTime = decodedBody["currentTime"] as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: currentTime / 1000.0)
    }

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/current-time.json"

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }
}
