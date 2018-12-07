//
//  RegionalAlertsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARegionalAlertsOperation)
public class RegionalAlertsOperation: NetworkOperation {
    private static let apiPath = "/api/gtfs_realtime/alerts-for-agency/%@.pb"

    public static func buildAPIPath(agencyID: String) -> String {
        return String(format: apiPath, NetworkHelpers.escapePathVariable(agencyID))
    }

    public class func buildURL(agencyID: String, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        return _buildURL(fromBaseURL: baseURL, path: buildAPIPath(agencyID: agencyID), queryItems: queryItems)
    }
}
