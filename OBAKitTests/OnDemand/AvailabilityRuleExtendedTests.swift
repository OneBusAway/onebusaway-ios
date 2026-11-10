//
//  AvailabilityRuleExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `AvailabilityRule` JSON decoding, optional GTFSTimeOfDay handling,
/// blank booking rule ID filtering, and hash behavior.
@Suite(.serialized)
struct AvailabilityRuleExtendedTests {

    private func makeJSON(
        fromIDs: [String] = ["zone_1"],
        toIDs: [String] = ["zone_2"],
        startPickupTime: String? = "08:00:00",
        endPickupTime: String? = "18:00:00",
        endDropOffTime: String? = "19:00:00",
        calendarIDs: [String] = ["cal_weekday"],
        pickupType: Int = 2,
        dropOffType: Int = 2,
        pickupBookingRuleID: String? = "rule_p1",
        dropOffBookingRuleID: String? = "rule_d1",
        safeDurationFactor: Double? = 1.2,
        safeDurationOffset: Double? = 300.0
    ) -> Data {
        var dict: [String: Any] = [
            "fromIds": fromIDs,
            "toIds": toIDs,
            "calendarIds": calendarIDs,
            "pickupType": pickupType,
            "dropOffType": dropOffType
        ]
        if let startPickupTime { dict["startPickupTime"] = startPickupTime }
        if let endPickupTime { dict["endPickupTime"] = endPickupTime }
        if let endDropOffTime { dict["endDropOffTime"] = endDropOffTime }
        if let pickupBookingRuleID { dict["pickupBookingRuleId"] = pickupBookingRuleID }
        if let dropOffBookingRuleID { dict["dropOffBookingRuleId"] = dropOffBookingRuleID }
        if let safeDurationFactor { dict["safeDurationFactor"] = safeDurationFactor }
        if let safeDurationOffset { dict["safeDurationOffset"] = safeDurationOffset }

        return try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Decoding

    @Test func `AvailabilityRule decodes all fields properly`() throws {
        let data = makeJSON()
        let rule = try JSONDecoder().decode(AvailabilityRule.self, from: data)

        #expect(rule.fromIDs == ["zone_1"])
        #expect(rule.toIDs == ["zone_2"])
        #expect(rule.startPickupTime == GTFSTimeOfDay("08:00:00"))
        #expect(rule.endPickupTime == GTFSTimeOfDay("18:00:00"))
        #expect(rule.endDropOffTime == GTFSTimeOfDay("19:00:00"))
        #expect(rule.calendarIDs == ["cal_weekday"])
        #expect(rule.pickupType == 2)
        #expect(rule.dropOffType == 2)
        #expect(rule.pickupBookingRuleID == "rule_p1")
        #expect(rule.dropOffBookingRuleID == "rule_d1")
        #expect(rule.safeDurationFactor == 1.2)
        #expect(rule.safeDurationOffset == 300.0)
    }

    @Test func `AvailabilityRule handles 24-hour service with all times nil`() throws {
        let data = makeJSON(startPickupTime: nil, endPickupTime: nil, endDropOffTime: nil)
        let rule = try JSONDecoder().decode(AvailabilityRule.self, from: data)

        #expect(rule.startPickupTime == nil)
        #expect(rule.endPickupTime == nil)
        #expect(rule.endDropOffTime == nil)
    }

    @Test func `AvailabilityRule nilifies empty booking rule IDs`() throws {
        let data = makeJSON(pickupBookingRuleID: "", dropOffBookingRuleID: "")
        let rule = try JSONDecoder().decode(AvailabilityRule.self, from: data)

        #expect(rule.pickupBookingRuleID == nil)
        #expect(rule.dropOffBookingRuleID == nil)
    }

    // MARK: - Hashable and Member Collections

    @Test func `AvailabilityRule equality and Set uniqueness`() throws {
        let r1 = try JSONDecoder().decode(AvailabilityRule.self, from: makeJSON(pickupBookingRuleID: "p1"))
        let r2 = try JSONDecoder().decode(AvailabilityRule.self, from: makeJSON(pickupBookingRuleID: "p1"))
        let r3 = try JSONDecoder().decode(AvailabilityRule.self, from: makeJSON(pickupBookingRuleID: "p2"))

        #expect(r1 == r2)
        #expect(r1.hashValue == r2.hashValue)
        #expect(r1 != r3)

        let set: Set<AvailabilityRule> = [r1, r2, r3]
        #expect(set.count == 2)
    }
}
