//
//  CurrentTimeOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class CurrentTimeOperation: NetworkOperation {
    @objc public var currentTime: String? {
        guard
            let response = response,
            let dateString = response.allHeaderFields["Date"] as? String
        else {
            return nil
        }

        return dateString
    }

    // MARK: - API Call and URL Construction

    public static let apiPath = "/api/where/current-time.json"

    public override class func buildURL(withBaseURL URL: URL, params: [AnyHashable : Any]?) -> URL {
        var components = URLComponents(url: URL, resolvingAgainstBaseURL: false)!
        components.path = apiPath
        if let params = params {
            components.queryItems = NetworkHelpers.dictionary(toQueryItems: params)
        }

        return components.url!
    }
}
