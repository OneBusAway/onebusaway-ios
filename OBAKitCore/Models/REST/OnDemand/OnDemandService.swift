//
//  OnDemandService.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A bookable on-demand service (wiki §2.1): the entry of
/// `/api/ondemand/service/{id}` and the list element of the two list endpoints.
///
/// `@unchecked Sendable` per the `HasReferences` contract in `References.swift`:
/// every `var` below is written only by `init(from:)` and `loadReferences`,
/// before the instance crosses an isolation boundary.
public final class OnDemandService: NSObject, Identifiable, Decodable, HasReferences, @unchecked Sendable {
    /// Combined ID; for flex services equal to the route's combined ID.
    public let id: String
    public let agencyID: String
    /// Nil for future GOFS-sourced services.
    public let routeID: String?
    public let name: String
    public let serviceKind: ServiceKind
    public let serviceDescription: String?
    public let url: URL?
    /// May be empty for degenerate feeds (wiki §2.3).
    public let rules: [AvailabilityRule]
    /// Only on `services-for-location` list elements.
    public let matchReason: MatchReason?

    // Resolved by `loadReferences`.
    public private(set) var route: Route?
    public private(set) var agency: Agency?
    /// Areas any rule starts or ends in, sorted by id.
    public private(set) var areas: [ServiceArea] = []
    public private(set) var locationGroups: [OnDemandLocationGroup] = []
    public private(set) var bookingRules: [OnDemandBookingRule] = []
    public private(set) var calendars: [OnDemandCalendar] = []
    public private(set) var regionIdentifier: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, serviceKind, url, rules, matchReason
        case agencyID = "agencyId"
        case routeID = "routeId"
        case serviceDescription = "description"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agencyID = try container.decode(String.self, forKey: .agencyID)
        routeID = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .routeID))
        name = try container.decode(String.self, forKey: .name)
        serviceKind = try container.decodeIfPresent(ServiceKind.self, forKey: .serviceKind) ?? .unknown
        serviceDescription = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .serviceDescription))
        url = String.nilifyBlankValue(try container.decodeIfPresent(String.self, forKey: .url)).flatMap(URL.init(string:))
        rules = try container.decodeIfPresent([AvailabilityRule].self, forKey: .rules) ?? []
        matchReason = try container.decodeIfPresent(MatchReason.self, forKey: .matchReason)
        super.init()
    }

    // MARK: - HasReferences

    public func loadReferences(_ references: References, regionIdentifier: Int?) {
        self.regionIdentifier = regionIdentifier
        route = references.routeWithID(routeID)
        agency = references.agencyWithID(agencyID)

        // Rules are the only link from a service to its areas and groups; the
        // ID namespace is shared, so each endpoint ID is tried against both.
        let endpointIDs = Set(rules.flatMap { $0.fromIDs + $0.toIDs }).sorted()
        areas = endpointIDs.compactMap { references.serviceAreaWithID($0) }
        locationGroups = endpointIDs.compactMap { references.locationGroupWithID($0) }

        let bookingRuleIDs = Set(rules.flatMap { [$0.pickupBookingRuleID, $0.dropOffBookingRuleID].compactMap { $0 } }).sorted()
        bookingRules = bookingRuleIDs.compactMap { references.bookingRuleWithID($0) }

        // Booking rules may reference a notice calendar of their own (spec §6.1).
        let calendarIDs = Set(rules.flatMap(\.calendarIDs) + bookingRules.compactMap(\.priorNoticeCalendarID)).sorted()
        calendars = calendarIDs.compactMap { references.calendarWithID($0) }
    }

    // MARK: - Lookups

    /// The booking rule with `id`, or nil when `id` is nil or the reference is
    /// missing. Callers must treat "referenced but missing" as unknown, not as
    /// "no notice required" — see `OnDemandServiceSummary`.
    public func bookingRule(id: String?) -> OnDemandBookingRule? {
        guard let id else { return nil }
        return bookingRules.first { $0.id == id }
    }

    /// The agency's time zone — the zone every service-day value is interpreted
    /// in (wiki §2.4). Nil until references load, or when the agency publishes
    /// an unknown identifier.
    public var timeZone: TimeZone? {
        agency?.resolvedTimeZone
    }

    // MARK: - CustomDebugStringConvertible

    public override var debugDescription: String {
        var builder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        builder.add(key: "id", value: id)
        builder.add(key: "name", value: name)
        builder.add(key: "serviceKind", value: serviceKind.rawValue)
        return builder.description
    }
}
