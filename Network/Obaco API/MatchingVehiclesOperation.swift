//
//  MatchingVehiclesOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class MatchingVehiclesOperation: NetworkOperation {

    private static let apiPath = "/api/v1/regions/%@/vehicles"
    public class func buildAPIPath(regionID: String) -> String {
        return String(format: apiPath, regionID)
    }

    public class func buildURL(query: String, regionID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let queryItem = URLQueryItem(name: "query", value: query)
        return buildURL(
            fromBaseURL: baseURL,
            path: buildAPIPath(regionID: regionID),
            queryItems: [queryItem] + queryItems
        )
    }

}
