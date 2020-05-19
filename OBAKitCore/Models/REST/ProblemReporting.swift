//
//  ProblemReporting.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 4/26/20.
//

import Foundation

// MARK: - Stop Problems

public enum StopProblemCode: Int, CaseIterable {
    case nameWrong
    case numberWrong
    case locationWrong
    case routeOrTripMissing
    case other

    public var APIStringValue: String {
        switch self {
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

    public var userFriendlyStringValue: String {
        switch self {
        case .nameWrong: return OBALoc("stop_problem_code.user_description.name_wrong", value: "Name is wrong", comment: "User-facing string that means the name of the stop is wrong.")
        case .numberWrong: return OBALoc("stop_problem_code.user_description.number_wrong", value: "Number is wrong", comment: "User-facing string that means the number/ID of the stop is wrong.")
        case .locationWrong: return OBALoc("stop_problem_code.user_description.location_wrong", value: "Location is wrong", comment: "User-facing string that means the location of the stop on the map is wrong.")
        case .routeOrTripMissing: return OBALoc("stop_problem_code.user_description.route_or_trip_missing", value: "Route or scheduled trip is missing", comment: "User-facing string that means our data is wrong about a route or a scheduled trip")
        case .other: return OBALoc("stop_problem_code.user_description.other", value: "Other", comment: "User-facing string that means that something else is wrong")
        }
    }
}

// MARK: - Trip Problems

public enum TripProblemCode: Int, CaseIterable {
    case neverCame
    case cameEarly
    case cameLate
    case wrongHeadsign
    case doesNotStopHere
    case other

    public var APIStringValue: String {
        switch self {
        case .neverCame: return "vehicle_never_came"
        case .cameEarly: return "vehicle_came_early"
        case .cameLate:  return "vehicle_came_late"
        case .wrongHeadsign: return "wrong_headsign"
        case .doesNotStopHere: return "vehicle_does_not_stop_here"
        case .other: return "other"
        }
    }

    public var userFriendlyStringValue: String {
        switch self {
        case .neverCame: return OBALoc("trip_problem_code.user_description.never_came", value: "Never came", comment: "User-facing string that means the vehicle never came.")
        case .cameEarly: return OBALoc("trip_problem_code.user_description.came_early", value: "Came early", comment: "User-facing string that means the vehicle came early.")
        case .cameLate: return OBALoc("trip_problem_code.user_description.came_late", value: "Came late", comment: "User-facing string that means the vehicle came late.")
        case .wrongHeadsign: return OBALoc("trip_problem_code.user_description.wrong_headsign", value: "Wrong headsign", comment: "User-facing string that means the vehicle headsign was wrong.")
        case .doesNotStopHere: return OBALoc("trip_problem_code.user_description.does_not_stop_here", value: "Does not stop here", comment: "User-facing string that means the vehicle does not stop here.")
        case .other: return OBALoc("trip_problem_code.user_description.other", value: "Other", comment: "User-facing string that means that something else is wrong")
        }
    }
}
