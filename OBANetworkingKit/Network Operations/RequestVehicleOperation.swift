//
//  RequestVehicleOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RequestVehicleOperation: WrappedResponseNetworkOperation {

    // MARK: - API Call and URL Construction

    private static let apiPath = "/api/where/vehicle/%@.json"

    public class func buildAPIPath(vehicleID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(vehicleID))
    }

    public class func buildURL(vehicleID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = buildAPIPath(vehicleID: vehicleID)
        components.queryItems = queryItems
        return components.url!
    }
}
