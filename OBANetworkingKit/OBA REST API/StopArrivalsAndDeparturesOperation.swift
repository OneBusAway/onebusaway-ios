//
//  StopArrivalsAndDeparturesOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAStopArrivalsAndDeparturesOperation)
public class StopArrivalsAndDeparturesOperation: RESTAPIOperation {

    private static let apiPath = "/api/where/arrivals-and-departures-for-stop/%@.json"

    public static func buildAPIPath(stopID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(stopID))
    }

    public class func buildURL(stopID: String, minutesBefore: UInt, minutesAfter: UInt, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = buildAPIPath(stopID: stopID)

        var args: [String: Any] = [:]
        args["minutesBefore"] = minutesBefore
        args["minutesAfter"] = minutesAfter

        components.queryItems = NetworkHelpers.dictionary(toQueryItems: args) + queryItems
        return components.url!
    }
}
