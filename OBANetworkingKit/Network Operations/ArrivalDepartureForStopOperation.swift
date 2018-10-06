//
//  ArrivalDepartureForStopOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAArrivalDepartureForStopOperation)
public class ArrivalDepartureForStopOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/arrival-and-departure-for-stop/%@.json"

    public class func buildAPIPath(stopID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(stopID))
    }

    public class func buildURL(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = buildAPIPath(stopID: stopID)

        var args: [String: Any] = [
            "serviceDate": serviceDate,
            "tripId": tripID
        ]

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        if stopSequence > 0 {
            args["stopSequence"] = stopSequence
        }

        components.queryItems = NetworkHelpers.dictionary(toQueryItems: args) + defaultQueryItems
        return components.url!
    }
}
