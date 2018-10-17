//
//  TripDetailsOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBATripDetailsOperation)
public class TripDetailsOperation: RESTAPIOperation {
    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/trip-details/%@.json"

    public class func buildAPIPath(tripID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(tripID))
    }

    public class func buildURL(tripID: String, vehicleID: String?, serviceDate: Int64, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var args: [String: Any] = [:]
        if serviceDate > 0 {
            args["serviceDate"] = serviceDate
        }

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        return _buildURL(fromBaseURL: baseURL, path: buildAPIPath(tripID: tripID), queryItems: NetworkHelpers.dictionary(toQueryItems: args) + queryItems)
    }
}
