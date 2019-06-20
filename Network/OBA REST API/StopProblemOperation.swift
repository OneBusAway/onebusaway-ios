//
//  StopProblemOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/12/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

public enum StopProblemCode: Int, CaseIterable {
    case nameWrong
    case numberWrong
    case locationWrong
    case routeOrTripMissing
    case other
}

func stopProblemCodeToAPIString(_ code: StopProblemCode) -> String {
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

func stopProblemCodeToUserFacingString(_ code: StopProblemCode) -> String {
    switch code {
    case .nameWrong: return NSLocalizedString("stop_problem_code.user_description.name_wrong", value: "Name is wrong", comment: "User-facing string that means the name of the stop is wrong.")
    case .numberWrong: return NSLocalizedString("stop_problem_code.user_description.number_wrong", value: "Number is wrong", comment: "User-facing string that means the number/ID of the stop is wrong.")
    case .locationWrong: return NSLocalizedString("stop_problem_code.user_description.location_wrong", value: "Location is wrong", comment: "User-facing string that means the location of the stop on the map is wrong.")
    case .routeOrTripMissing: return NSLocalizedString("stop_problem_code.user_description.route_or_trip_missing", value: "Route or scheduled trip is missing", comment: "User-facing string that means our data is wrong about a route or a scheduled trip")
    case .other: return NSLocalizedString("stop_problem_code.user_description.other", value: "Other", comment: "User-facing string that means that something else is wrong")
    }
}

public class StopProblemOperation: RESTAPIOperation {

    public static let apiPath = "/api/where/report-problem-with-stop.json"

    public class func buildURL(stopID: String, code: StopProblemCode, comment: String?, location: CLLocation?, baseURL: URL, queryItems: [URLQueryItem]) -> URL {
        var args: [String: Any] = [
            "stopId": stopID,
            "code": stopProblemCodeToAPIString(code)
        ]

        if let comment = comment {
            args["userComment"] = comment
        }

        if let location = location {
            args["userLat"] = location.coordinate.latitude
            args["userLon"] = location.coordinate.longitude
            args["userLocationAccuracy"] = location.horizontalAccuracy
        }

        return buildURL(fromBaseURL: baseURL, path: apiPath, queryItems: NetworkHelpers.dictionary(toQueryItems: args) + queryItems)
    }
}
