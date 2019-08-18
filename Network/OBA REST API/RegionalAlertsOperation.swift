//
//  RegionalAlertsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The opertion for fetching data from the `alerts-for-agency` ProtoBuf REST API endpoint.
public class RegionalAlertsOperation: NetworkOperation {
    // MARK: - REST API
    private static let restAPIPath = "/api/gtfs_realtime/alerts-for-agency/%@.pb"

    public class func buildRESTAPIPath(agencyID: String) -> String {
        String(format: restAPIPath, NetworkHelpers.escapePathVariable(agencyID))
    }

    public class func buildRESTURL(agencyID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let apiPath = buildRESTAPIPath(agencyID: agencyID)
        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }

    // MARK: - Obaco API

    private static let obacoAPIPath = "/api/v1/regions/%@/alerts.pb"

    public class func buildObacoAPIPath(regionID: String) -> String {
        String(format: obacoAPIPath, NetworkHelpers.escapePathVariable(regionID))
    }

    public class func buildObacoURL(regionID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        let apiPath = buildObacoAPIPath(regionID: regionID)
        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: queryItems)
    }
}
