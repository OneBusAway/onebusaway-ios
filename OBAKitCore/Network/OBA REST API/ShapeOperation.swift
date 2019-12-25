//
//  ShapeOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The operation for loading data from the `/api/where/shape/{shape_id}.json` endpoint.
public class ShapeOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/shape/%@.json"

    public class func buildAPIPath(shapeID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(shapeID))
    }

    public class func buildURL(shapeID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let builder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: queryItems)
        return builder.generateURL(path: buildAPIPath(shapeID: shapeID))
    }
}
