//
//  StopArrivalsAndDeparturesOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

public class StopArrivalsAndDeparturesOperation: RESTAPIOperation {

    private static let apiPath = "/api/where/arrivals-and-departures-for-stop/%@.json"

    public static func buildAPIPath(stopID: StopID) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(stopID))
    }

    public class func buildURL(stopID: StopID, minutesBefore: UInt, minutesAfter: UInt, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let builder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: queryItems)
        return builder.generateURL(path: buildAPIPath(stopID: stopID), params: [
            "minutesBefore": minutesBefore,
            "minutesAfter": minutesAfter
        ])
    }
}
