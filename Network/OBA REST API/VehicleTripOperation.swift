//
//  VehicleTripOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAVehicleTripOperation)
public class VehicleTripOperation: RESTAPIOperation {

    private static let apiPath = "/api/where/trip-for-vehicle/%@.json"
    public class func buildAPIPath(vehicleID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(vehicleID))
    }

    public class func buildURL(vehicleID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let path = buildAPIPath(vehicleID: vehicleID)
        return buildURL(fromBaseURL: baseURL, path: path, queryItems: queryItems)
    }
}
