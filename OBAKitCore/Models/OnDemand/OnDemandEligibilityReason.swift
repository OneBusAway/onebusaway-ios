//
//  OnDemandEligibilityReason.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// The typed, explainable reason for an on-demand booking or trip eligibility outcome.
public enum OnDemandEligibilityReason: Hashable, Sendable, CustomStringConvertible {

    /// The endpoint that was missing from an evaluation request.
    public enum EndpointType: String, Hashable, Sendable {
        case origin
        case destination
        case both
    }

    /// The zone failure that prevented eligibility.
    public enum ZoneFailure: Hashable, Sendable {
        case originOutside
        case destinationOutside
        case disconnected
        case pointOutside
    }

    /// The condition making an on-demand service unavailable for booking.
    public enum UnavailableReason: Hashable, Sendable {
        case missingTimeZone
        case noServiceOnDate(ServiceDate)
        case serviceEnded
        case certificationRequired
        case unresolvedBookingRule
        case noRules
    }

    /// Eligible for booking. Carries the cutoff instant when one is enforced,
    /// or nil when no advance notice is required.
    case eligible(cutoff: Date?)

    /// Booking has not opened yet. Booking opens at `openInstant`.
    case tooEarly(openInstant: Date)

    /// Booking deadline has passed for the travel date. Cutoff occurred at `cutoffInstant`.
    case tooLate(cutoffInstant: Date)

    /// Location is outside the service area or no route connects the zones.
    case outsideZone(ZoneFailure)

    /// A required endpoint (origin, destination, or both) was missing.
    case missingEndpoint(EndpointType)

    /// Service cannot be booked due to schedule, missing configuration, or restrictions.
    case unavailable(UnavailableReason)

    /// Whether this reason indicates that booking is currently permitted.
    public var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    /// Technical domain-level explanation string (unlocalized, suitable for logging and debugging).
    public var domainExplanation: String {
        switch self {
        case .eligible(let cutoff):
            if let cutoff {
                return "Eligible for booking until \(cutoff)."
            } else {
                return "Eligible for booking."
            }
        case .tooEarly(let openInstant):
            return "Booking has not opened yet. Opens at \(openInstant)."
        case .tooLate(let cutoffInstant):
            return "Booking deadline passed at \(cutoffInstant)."
        case .outsideZone(let zoneFailure):
            switch zoneFailure {
            case .originOutside:
                return "Trip origin is outside the service area."
            case .destinationOutside:
                return "Trip destination is outside the service area."
            case .disconnected:
                return "Service does not operate between the specified origin and destination zones."
            case .pointOutside:
                return "Specified location is outside the service area."
            }
        case .missingEndpoint(let endpointType):
            switch endpointType {
            case .origin:
                return "Missing trip origin endpoint."
            case .destination:
                return "Missing trip destination endpoint."
            case .both:
                return "Missing trip origin and destination endpoints."
            }
        case .unavailable(let reason):
            switch reason {
            case .missingTimeZone:
                return "Service is unavailable: agency time zone is unknown."
            case .noServiceOnDate(let date):
                return "Service is unavailable: no service scheduled on \(date)."
            case .serviceEnded:
                return "Service is unavailable: calendar service period has ended."
            case .certificationRequired:
                return "Service requires rider eligibility certification."
            case .unresolvedBookingRule:
                return "Service is unavailable: booking rules could not be resolved."
            case .noRules:
                return "Service is unavailable: no service rules defined."
            }
        }
    }

    public var description: String { domainExplanation }
}
