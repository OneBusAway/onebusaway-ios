//
//  StopProblemOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBAStopProblemType)
public enum StopProblemCode: Int {
    case nameWrong
    case numberWrong
    case locationWrong
    case routeOrTripMissing
    case other
}

func stopProblemCodeToString(_ code: StopProblemCode) -> String {
    switch code {
    case .nameWrong:
        return "stop_name_wrong"
    case .numberWrong:
        return "stop_number_wrong"
    case .locationWrong:
        return "stop_location_wrong"
    case .routeOrTripMissing:
        return "route_or_trip_missing"
    case .other:
        return "other"
    }
}

@objc(OBAStopProblemOperation)
public class StopProblemOperation: RESTAPIOperation {

    public static let apiPath = "/api/where/report-problem-with-stop.json"

    public class func buildURL(stopID: String, code: StopProblemCode, comment: String?, location: CLLocation?, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var args: [AnyHashable: Any] = [
            "stopId": stopID,
            "code": stopProblemCodeToString(code)
        ]

        if let comment = comment {
            args["userComment"] = comment
        }

        if let location = location {
            args["userLat"] = location.coordinate.latitude
            args["userLon"] = location.coordinate.longitude
            args["userLocationAccuracy"] = location.horizontalAccuracy
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = apiPath
        components.queryItems = NetworkHelpers.dictionary(toQueryItems: args) + queryItems
        return components.url!
    }
}
