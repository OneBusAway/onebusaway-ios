//
//  StopProblemOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBAStopProblemOperation)
public class StopProblemOperation: RESTAPIOperation {

    public class func buildURLRequest(stopID: String, code: String?, comment: String?, location: CLLocation?, baseURL: URL, queryItems: [URLQueryItem]) -> URLRequest {
        var args: [AnyHashable: Any] = [
            "stopId": stopID
        ]

        if let code = code {
            args["code"] = code
        }

        if let comment = comment {
            args["userComment"] = comment
        }

        if let location = location {
            args["userLat"] = location.coordinate.latitude
            args["userLon"] = location.coordinate.longitude
            args["userLocationAccuracy"] = location.horizontalAccuracy
        }

        let url = buildURL(baseURL: baseURL, queryItems: queryItems)
        let request = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: args)

        return request as URLRequest
    }

    public static let apiPath = "/api/where/report-problem-with-stop.json"

    private class func buildURL(baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = apiPath

        components.queryItems = queryItems
        return components.url!
    }
}
