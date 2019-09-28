//
//  AgenciesWithCoverageOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The operation for loading the `/api/where/agencies-with-coverage.json` endpoint.
public class AgenciesWithCoverageOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/agencies-with-coverage.json"

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }
}
