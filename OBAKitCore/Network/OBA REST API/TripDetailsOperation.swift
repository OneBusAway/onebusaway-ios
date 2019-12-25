//
//  TripDetailsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class TripDetailsOperation: RESTAPIOperation {
    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/trip-details/%@.json"

    public class func buildAPIPath(tripID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(tripID))
    }

    public class func buildURL(
        tripID: String,
        vehicleID: String?,
        serviceDate: Date?,
        baseURL: URL,
        queryItems: [URLQueryItem]
    ) -> URL {
        var args: [String: Any] = [:]
        if let serviceDate = serviceDate {
            args["serviceDate"] = Int64(serviceDate.timeIntervalSince1970 * 1000)
        }

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        let builder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: queryItems)
        return builder.generateURL(path: buildAPIPath(tripID: tripID), params: args)
    }
}
