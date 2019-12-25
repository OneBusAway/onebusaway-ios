//
//  RequestVehicleOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RequestVehicleOperation: RESTAPIOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/vehicle/%@.json"

    public class func buildAPIPath(vehicleID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(vehicleID))
    }

    public class func buildURL(vehicleID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let builder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: queryItems)
        return builder.generateURL(path: buildAPIPath(vehicleID: vehicleID))
    }
}
