//
//  TripProblemOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBATripProblemCode)
public enum TripProblemCode: Int, CaseIterable {
    case neverCame
    case cameEarly
    case cameLate
    case wrongHeadsign
    case doesNotStopHere
    case other
}

func tripProblemCodeToString(_ code: TripProblemCode) -> String {
    switch code {
    case .neverCame: return "vehicle_never_came"
    case .cameEarly: return "vehicle_came_early"
    case .cameLate:  return "vehicle_came_late"
    case .wrongHeadsign: return "wrong_headsign"
    case .doesNotStopHere: return "vehicle_does_not_stop_here"
    case .other: return "other"
    }
}

func tripProblemCodeToUserFacingString(_ code: TripProblemCode) -> String {
    switch code {
    case .neverCame: return NSLocalizedString("trip_problem_code.user_description.never_came", value: "Never came", comment: "User-facing string that means the vehicle never came.")
    case .cameEarly: return NSLocalizedString("trip_problem_code.user_description.came_early", value: "Came early", comment: "User-facing string that means the vehicle came early.")
    case .cameLate: return NSLocalizedString("trip_problem_code.user_description.came_late", value: "Came late", comment: "User-facing string that means the vehicle came late.")
    case .wrongHeadsign: return NSLocalizedString("trip_problem_code.user_description.wrong_headsign", value: "Wrong headsign", comment: "User-facing string that means the vehicle headsign was wrong.")
    case .doesNotStopHere: return NSLocalizedString("trip_problem_code.user_description.does_not_stop_here", value: "Does not stop here", comment: "User-facing string that means the vehicle does not stop here.")
    case .other: return NSLocalizedString("trip_problem_code.user_description.other", value: "Other", comment: "User-facing string that means that something else is wrong")
    }
}

@objc(OBATripProblemOperation)
public class TripProblemOperation: RESTAPIOperation {
    public static let apiPath = "/api/where/report-problem-with-trip.json"

    public static func buildURL(tripID: String, serviceDate: Date, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, baseURL: URL, queryItems: [URLQueryItem]) -> URL {

        var args: [String: Any] = [
            "tripId": tripID,
            "serviceDate": Int64(serviceDate.timeIntervalSince1970 * 1000),
            "code": tripProblemCodeToString(code),
            "userOnVehicle": userOnVehicle ? "true" : "false"
        ]

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        if let stopID = stopID {
            args["stopId"] = stopID
        }

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
