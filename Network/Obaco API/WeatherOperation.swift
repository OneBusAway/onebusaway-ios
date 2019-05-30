//
//  WeatherOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/17/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAWeatherOperation)
public class WeatherOperation: NetworkOperation {

    private static let apiPath = "/api/v1/regions/%@/weather.json"

    public class func buildAPIPath(regionID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(regionID))
    }

    public class func buildURL(regionID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return buildURL(fromBaseURL: baseURL, path: buildAPIPath(regionID: regionID), queryItems: queryItems)
    }
}
