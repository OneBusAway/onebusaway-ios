//
//  TripArrivalDepartureOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBATripArrivalDepartureOperation)
public class TripArrivalDepartureOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/arrival-and-departure-for-stop/%@.json"

    public class func buildAPIPath(stopID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(stopID))
    }

    public class func buildURL(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, baseURL: URL, defaultQueryItems: [URLQueryItem]) -> URL {

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

        return _buildURL(fromBaseURL: baseURL, path: buildAPIPath(stopID: stopID), queryItems: NetworkHelpers.dictionary(toQueryItems: args) + defaultQueryItems)
    }
}
