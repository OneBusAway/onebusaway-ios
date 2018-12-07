//
//  CurrentTimeOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class CurrentTimeOperation: RESTAPIOperation {
    @objc public var currentTime: Date? {
        guard
            let decodedBody = _decodedJSONBody as? [String: Any],
            let currentTime = decodedBody["currentTime"] as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: currentTime / 1000.0)
    }

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/current-time.json"

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return _buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }
}
