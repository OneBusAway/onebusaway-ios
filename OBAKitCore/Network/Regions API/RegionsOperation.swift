//
//  RegionsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/16/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RegionsOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    public static let apiPath = "/regions-v3.json"

    public class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }
}
