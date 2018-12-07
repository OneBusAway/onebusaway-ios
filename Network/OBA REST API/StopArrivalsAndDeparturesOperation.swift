//
//  StopArrivalsAndDeparturesOperation.swift
//  OBAKit
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
        let args: [String: Any] = [
            "minutesBefore": minutesBefore,
            "minutesAfter": minutesAfter
        ]

        return _buildURL(fromBaseURL: baseURL, path: buildAPIPath(stopID: stopID), queryItems: NetworkHelpers.dictionary(toQueryItems: args) + queryItems)
    }
}
