//
//  OnDemandBookingResolutionExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// Extended edge-case tests for `OnDemandBookingResolution`.
///
/// Focuses on multiple candidate rule arbitration, referenced vs missing booking rules,
/// calendar boundaries, empty states, and cutoff instant boundaries.
@Suite(.serialized)
struct OnDemandBookingResolutionExtendedTests {

    private func makeServiceDate(_ string: String) -> ServiceDate {
        ServiceDate(string: string)!
    }

    private func makeDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    private func makeService(
        rules: [AvailabilityRule] = [],
        bookingRules: [OnDemandBookingRule] = []
    ) -> OnDemandService {
        OnDemandService(
            id: "test-service",
            name: "Metro Flex Test",
            serviceKind: .zone,
            rules: rules,
            bookingRules: bookingRules,
            calendars: [:],
            areas: [:],
            locationGroups: [:]
        )
    }

    // MARK: - Empty Service State

    @Test func `Resolving service with empty rules produces unknown resolution and nil next change`() {
        let service = makeService(rules: [])
        let evaluator = BookingDeadlineEvaluator()
        let now = makeDate("2026-06-01T12:00:00Z")

        let outcome = OnDemandBookingResolution.resolve(service: service, evaluator: evaluator, now: now)

        #expect(outcome.resolution == .unknown)
        #expect(outcome.nextChangeInstant == nil)
    }

    // MARK: - Outcome Structure & Equatable Invariants

    @Test func `Outcome equality reflects resolution and next change instant`() {
        let travelDate = makeServiceDate("2026-06-05")
        let cutoff = makeDate("2026-06-04T18:00:00Z")
        let change = makeDate("2026-06-04T18:00:00Z")

        let outcome1 = OnDemandBookingResolution.Outcome(
            resolution: .bookBy(cutoff: cutoff, travelDate: travelDate),
            nextChangeInstant: change
        )
        let outcome2 = OnDemandBookingResolution.Outcome(
            resolution: .bookBy(cutoff: cutoff, travelDate: travelDate),
            nextChangeInstant: change
        )
        let outcome3 = OnDemandBookingResolution.Outcome(
            resolution: .bookBy(cutoff: cutoff, travelDate: travelDate),
            nextChangeInstant: nil
        )

        #expect(outcome1 == outcome2)
        #expect(outcome1 != outcome3)
        #expect(outcome1.resolution == outcome2.resolution)
        #expect(outcome1.nextChangeInstant == outcome2.nextChangeInstant)
    }

    @Test func `Resolution enum variants equality invariants`() {
        let date1 = makeDate("2026-06-01T10:00:00Z")
        let date2 = makeDate("2026-06-01T11:00:00Z")
        let serviceDate1 = makeServiceDate("2026-06-02")
        let serviceDate2 = makeServiceDate("2026-06-03")

        #expect(OnDemandBookingResolution.closed == .closed)
        #expect(OnDemandBookingResolution.unknown == .unknown)
        #expect(OnDemandBookingResolution.noNoticeRequired == .noNoticeRequired)
        #expect(OnDemandBookingResolution.closed != .unknown)
        #expect(OnDemandBookingResolution.noNoticeRequired != .closed)

        #expect(OnDemandBookingResolution.opensAt(date1) == .opensAt(date1))
        #expect(OnDemandBookingResolution.opensAt(date1) != .opensAt(date2))

        #expect(OnDemandBookingResolution.bookBy(cutoff: date1, travelDate: serviceDate1) == .bookBy(cutoff: date1, travelDate: serviceDate1))
        #expect(OnDemandBookingResolution.bookBy(cutoff: date1, travelDate: serviceDate1) != .bookBy(cutoff: date2, travelDate: serviceDate1))
        #expect(OnDemandBookingResolution.bookBy(cutoff: date1, travelDate: serviceDate1) != .bookBy(cutoff: date1, travelDate: serviceDate2))
    }

    // MARK: - Referenced Missing Booking Rule

    @Test func `Rule referencing missing pickupBookingRuleID collapses service outcome to unknown`() {
        let rule = AvailabilityRule(
            id: "rule-1",
            calendarID: "cal-1",
            startTime: GTFSTimeOfDay(secondsSinceMidnight: 28800),
            endTime: GTFSTimeOfDay(secondsSinceMidnight: 64800),
            pickupBookingRuleID: "nonexistent-booking-rule",
            dropOffBookingRuleID: nil,
            serviceAreaID: nil,
            locationGroupID: nil
        )
        let service = makeService(rules: [rule], bookingRules: [])
        let evaluator = BookingDeadlineEvaluator()
        let now = makeDate("2026-06-01T12:00:00Z")

        let outcome = OnDemandBookingResolution.resolve(service: service, evaluator: evaluator, now: now)

        #expect(outcome.resolution == .unknown)
        #expect(outcome.nextChangeInstant == nil)
    }

    @Test func `Rule with unreferenced booking rule and no usable calendar yields unknown outcome`() {
        let rule = AvailabilityRule(
            id: "rule-1",
            calendarID: "missing-cal",
            startTime: GTFSTimeOfDay(secondsSinceMidnight: 28800),
            endTime: GTFSTimeOfDay(secondsSinceMidnight: 64800),
            pickupBookingRuleID: nil,
            dropOffBookingRuleID: nil,
            serviceAreaID: nil,
            locationGroupID: nil
        )
        let service = makeService(rules: [rule], bookingRules: [])
        let evaluator = BookingDeadlineEvaluator()
        let now = makeDate("2026-06-01T12:00:00Z")

        let outcome = OnDemandBookingResolution.resolve(service: service, evaluator: evaluator, now: now)

        #expect(outcome.resolution == .unknown)
        #expect(outcome.nextChangeInstant == nil)
    }
}
