//
//  CurrentTimeOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class CurrentTimeOperation: RESTAPIOperation {
    @objc public var currentTime: String? {
        guard
            let response = response,
            let dateString = response.allHeaderFields["Date"] as? String
        else {
            return nil
        }

        return dateString
    }

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/current-time.json"

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = apiPath
        components.queryItems = queryItems

        return components.url!
    }
}
