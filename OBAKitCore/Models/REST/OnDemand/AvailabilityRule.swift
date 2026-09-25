//
//  AvailabilityRule.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// One "from these places, to these places, in this daily window, on this
/// calendar" statement of an on-demand service (wiki §2.2). All three time
/// fields nil means the service runs all hours of its service days.
public struct AvailabilityRule: Decodable, Hashable, Sendable {
    /// Shared stop / location / location-group ID namespace.
    public let fromIDs: [String]
    public let toIDs: [String]
    public let startPickupTime: GTFSTimeOfDay?
    public let endPickupTime: GTFSTimeOfDay?
    /// Nil when it equals `endPickupTime`.
    public let endDropOffTime: GTFSTimeOfDay?
    /// At least one element on the wire; → `references.calendars`.
    public let calendarIDs: [String]
    /// 0 scheduled, 2 must book, 3 coordinate with driver.
    public let pickupType: Int
    public let dropOffType: Int
    /// The pickup side governs booking (spec §6); → `references.bookingRules`.
    public let pickupBookingRuleID: String?
    public let dropOffBookingRuleID: String?
    public let safeDurationFactor: Double?
    /// Seconds.
    public let safeDurationOffset: Double?

    private enum CodingKeys: String, CodingKey {
        case fromIds, toIds, startPickupTime, endPickupTime, endDropOffTime, calendarIds
        case pickupType, dropOffType, pickupBookingRuleId, dropOffBookingRuleId
        case safeDurationFactor, safeDurationOffset
    }

    public init(
        fromIDs: [String],
        toIDs: [String],
        startPickupTime: GTFSTimeOfDay?,
        endPickupTime: GTFSTimeOfDay?,
        endDropOffTime: GTFSTimeOfDay?,
        calendarIDs: [String],
        pickupType: Int,
        dropOffType: Int,
        pickupBookingRuleID: String?,
        dropOffBookingRuleID: String?,
        safeDurationFactor: Double?,
        safeDurationOffset: Double?
    ) {
        self.fromIDs = fromIDs
        self.toIDs = toIDs
        self.startPickupTime = startPickupTime
        self.endPickupTime = endPickupTime
        self.endDropOffTime = endDropOffTime
        self.calendarIDs = calendarIDs
        self.pickupType = pickupType
        self.dropOffType = dropOffType
        self.pickupBookingRuleID = pickupBookingRuleID
        self.dropOffBookingRuleID = dropOffBookingRuleID
        self.safeDurationFactor = safeDurationFactor
        self.safeDurationOffset = safeDurationOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fromIDs = try container.decode([String].self, forKey: .fromIds)
        toIDs = try container.decode([String].self, forKey: .toIds)
        startPickupTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .startPickupTime)
        endPickupTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .endPickupTime)
        endDropOffTime = try container.decodeIfPresent(GTFSTimeOfDay.self, forKey: .endDropOffTime)
        calendarIDs = try container.decode([String].self, forKey: .calendarIds)
        pickupType = try container.decode(Int.self, forKey: .pickupType)
        dropOffType = try container.decode(Int.self, forKey: .dropOffType)
        pickupBookingRuleID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .pickupBookingRuleId))
        dropOffBookingRuleID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .dropOffBookingRuleId))
        safeDurationFactor = try container.decodeIfPresent(Double.self, forKey: .safeDurationFactor)
        safeDurationOffset = try container.decodeIfPresent(Double.self, forKey: .safeDurationOffset)
    }
}
