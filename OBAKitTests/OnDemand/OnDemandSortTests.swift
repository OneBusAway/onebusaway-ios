//
//  OnDemandSortTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OnDemandSortTests: OBATestCase {

    private let today = ServiceDate(year: 2026, month: 3, day: 10)
    private let tomorrow = ServiceDate(year: 2026, month: 3, day: 11)

    private func service(id: String, name: String) throws -> OnDemandService {
        try Fixtures.dictionaryToModel(type: OnDemandService.self, dictionary: [
            "id": id, "agencyId": "CC", "routeId": id, "name": name, "serviceKind": "zone",
            "description": NSNull(), "url": NSNull(), "rules": []
        ])
    }

    private func availability(tier: Int, status: OnDemandStatus = .unknown) -> OnDemandAvailability {
        OnDemandAvailability(
            runningNow: false, runningUntil: nil, nextRunStart: nil, bookingTier: nil, bookableNow: false,
            nextBookableServiceDate: nil, status: status, tags: [], usabilityTier: tier, nextChangeInstant: nil
        )
    }

    private func match(id: String, name: String = "Zone", tier: Int, distance: Double?, reason: MatchReason = .areaNearby) throws -> OnDemandServiceMatch {
        OnDemandServiceMatch(
            service: try service(id: id, name: name),
            matchReason: reason,
            distanceToArea: distance,
            nearestPointOnBoundary: nil,
            availability: availability(tier: tier)
        )
    }

    // MARK: - Usability tier (spec 2.6)

    @Test func `Tier order is eligibility, open now, unknown or closed, same day, advance`() {
        let open = OnDemandStatus.openNow(until: nil)
        #expect(OnDemandAvailability.usabilityTier(status: open, tags: [.eligibilityRequired], nextBookableServiceDate: today, today: today) == 4)
        #expect(OnDemandAvailability.usabilityTier(status: open, tags: [], nextBookableServiceDate: nil, today: today) == 1)
        #expect(OnDemandAvailability.usabilityTier(status: .opensAt(Date()), tags: [], nextBookableServiceDate: today, today: today) == 2)
        #expect(OnDemandAvailability.usabilityTier(status: .opensAt(Date()), tags: [], nextBookableServiceDate: tomorrow, today: today) == 3)
        #expect(OnDemandAvailability.usabilityTier(status: .bookBy(deadline: Date(), travelDate: tomorrow), tags: [], nextBookableServiceDate: nil, today: today) == 5, "advance with no bookable date")
        #expect(OnDemandAvailability.usabilityTier(status: .closed, tags: [], nextBookableServiceDate: today, today: today) == 5, "closed with a bookable date")
        #expect(OnDemandAvailability.usabilityTier(status: .unknown, tags: [], nextBookableServiceDate: today, today: today) == 5)
    }

    // MARK: - Sort

    @Test func `Sorts by tier then distance then name`() throws {
        let sorted = sortedSoonestUsable([
            try match(id: "c", name: "C", tier: 3, distance: 0),
            try match(id: "b", name: "B", tier: 1, distance: 900),
            try match(id: "a", name: "A", tier: 1, distance: 100),
            try match(id: "d", name: "D", tier: 5, distance: nil),
            try match(id: "e", name: "E", tier: 2, distance: nil),
            try match(id: "f", name: "F", tier: 2, distance: 4000)
        ])
        #expect(sorted.map(\.id) == ["a", "b", "f", "e", "c", "d"])
    }

    @Test func `Names compare with natural order`() throws {
        let sorted = sortedSoonestUsable([
            try match(id: "10", name: "Zone 10", tier: 1, distance: 0),
            try match(id: "2", name: "Zone 2", tier: 1, distance: 0),
            try match(id: "1", name: "zone 1", tier: 1, distance: 0)
        ])
        #expect(sorted.map(\.id) == ["1", "2", "10"])
    }

    /// Review Focus 3: a total order even for duplicate names.
    @Test func `Equal tier, distance and name keep service id order`() throws {
        let sorted = sortedSoonestUsable([
            try match(id: "CC_CC4", name: "Dial-a-Ride", tier: 1, distance: 0),
            try match(id: "CC_CC1", name: "Dial-a-Ride", tier: 1, distance: 0)
        ])
        #expect(sorted.map(\.id) == ["CC_CC1", "CC_CC4"])
        #expect(sortedSoonestUsable(sorted).map(\.id) == ["CC_CC1", "CC_CC4"], "stable on re-sort")
    }

    // MARK: - Building matches from a probe response

    @Test func `Matches take the minimum area distance and its boundary point`() throws {
        let data = Fixtures.loadData(file: "ondemand_services_for_location_point_near.json")
        let services = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: data).list
        let matches = OnDemandServiceMatch.matches(from: services, now: ISO8601DateFormatter().date(from: "2026-03-10T16:00:00Z")!)
        #expect(matches.count == 1)
        #expect(matches[0].matchReason == .areaNearby)
        #expect(matches[0].distanceToArea == 850)
        #expect(matches[0].nearestPointOnBoundary?.latitude == 45.30765)
        #expect(matches[0].nearestPointOnBoundary?.longitude == -85.2)
        #expect(!matches[0].isInside)
        #expect(matches[0].isNearby)
        #expect(matches[0].availability.runningNow)
    }

    @Test func `Inside matches report zero distance and no boundary point`() throws {
        let data = Fixtures.loadData(file: "ondemand_services_for_location_point.json")
        let services = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<[OnDemandService]>.self, from: data).list
        let matches = OnDemandServiceMatch.matches(from: services, now: Date())
        #expect(matches[0].isInside)
        #expect(matches[0].distanceToArea == 0)
        #expect(matches[0].nearestPointOnBoundary == nil)
        #expect(!matches[0].isNearby)
    }

    /// Goes through the deriving initializer, so the nil distance comes from
    /// the service having no areas rather than from the test's own input.
    @Test func `A service without areas has a nil distance and is never nearby`() throws {
        let arealess = try service(id: "CC_CC3", name: "Ferry")
        #expect(arealess.areas.isEmpty)
        let match = OnDemandServiceMatch(service: arealess, availability: availability(tier: 1))
        #expect(match.distanceToArea == nil)
        #expect(match.nearestPointOnBoundary == nil)
        #expect(!match.isNearby)
    }

    @Test func `A finite distance beyond the radius is not nearby`() throws {
        #expect(!(try match(id: "x", tier: 1, distance: 5001).isNearby))
        #expect(try match(id: "y", tier: 1, distance: 5000).isNearby)
    }

    @Test func `Location check equality includes the coordinate`() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2)
        let a = OnDemandLocationCheck(source: .rider, isInside: true, locality: "Boyne City", coordinate: coordinate)
        let b = OnDemandLocationCheck(source: .rider, isInside: true, locality: "Boyne City", coordinate: coordinate)
        let c = OnDemandLocationCheck(source: .point(label: nil), isInside: true, locality: "Boyne City", coordinate: coordinate)
        #expect(a == b)
        #expect(a != c)
    }
}
