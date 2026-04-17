import Foundation
import CoreLocation

/// Represents a single itinerary (route) from an OpenTripPlanner request.
public struct OTPItinerary: Codable, Identifiable {
    public var id: String {
        return "\(startTime)-\(endTime)-\(duration)"
    }
    
    public let duration: TimeInterval
    public let startTime: Date
    public let endTime: Date
    public let walkTime: TimeInterval
    public let transitTime: TimeInterval
    public let waitingTime: TimeInterval
    public let walkDistance: Double
    public let transfers: Int
    public let legs: [OTPLeg]
}

/// Represents a single leg of an itinerary (e.g., a bus ride or a walk).
public struct OTPLeg: Codable, Identifiable {
    public var id: String {
        return "\(startTime)-\(endTime)-\(mode)"
    }
    
    public let startTime: Date
    public let endTime: Date
    public let mode: String // BUS, WALK, RAIL, etc.
    public let distance: Double
    public let duration: TimeInterval
    
    public let route: String?
    public let routeShortName: String?
    public let routeLongName: String?
    public let headsign: String?
    public let agencyName: String?
    
    public let from: OTPPlace
    public let to: OTPPlace
    
    public let legGeometry: OTPGeometry?
    public let steps: [OTPStep]?
}

/// Represents a location in an OTP request.
public struct OTPPlace: Codable {
    public let name: String
    public let lat: Double
    public let lon: Double
    public let stopId: String?
    public let stopCode: String?
}

/// Represents the geometry (polyline) of a leg.
public struct OTPGeometry: Codable {
    public let points: String
}

/// Represents a single step in a walking leg.
public struct OTPStep: Codable {
    public let distance: Double
    public let relativeDirection: String?
    public let streetName: String
    public let absoluteDirection: String?
    public let lat: Double
    public let lon: Double
}

/// Root response from an OTP plan request.
public struct OTPPlanResponse: Codable {
    public let plan: OTPPlan?
    public let error: OTPError?
}

public struct OTPPlan: Codable {
    public let date: Date
    public let from: OTPPlace
    public let to: OTPPlace
    public let itineraries: [OTPItinerary]
}

public struct OTPError: Codable {
    public let id: Int
    public let msg: String
}
