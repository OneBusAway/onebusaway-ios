//
//  ShapeOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAShapeOperation)
public class ShapeOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/shape/%@.json"

    public class func buildAPIPath(shapeID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(shapeID))
    }

    public class func buildURL(shapeID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = buildAPIPath(shapeID: shapeID)
        components.queryItems = queryItems
        return components.url!
    }
}
