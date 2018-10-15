//
//  TripProblemOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/14/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBATripProblemCode)
public enum TripProblemCode: Int {
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

@objc(OBATripProblemOperation)
public class TripProblemOperation: RESTAPIOperation {
    public static let apiPath = "/api/where/report-problem-with-trip.json"

    public static func buildURL(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, baseURL: URL, queryItems: [URLQueryItem]) -> URL {

        var args: [String: Any] = [
            "tripId": tripID,
            "serviceDate": serviceDate,
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
