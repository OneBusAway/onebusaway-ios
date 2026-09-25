//
//  Strings+OnDemand.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Localized strings for the on-demand (GTFS-Flex) surfaces: the map layer, the
/// service page, the stop-page section and the agency list.
public extension Strings {

    // MARK: - Map layer

    static let onDemandZonesLayer = OBALoc("map_layers.on_demand_zones", value: "On-demand zones", comment: "Map sheet row for the on-demand (dial-a-ride) service zones layer")

    static let onDemandZonesUnavailable = OBALoc("map_layers.on_demand_unavailable", value: "Not available right now", comment: "Reason shown on a dimmed on-demand zones layer row when the server is unreachable")

    // MARK: - Service page

    static let onDemandSectionTitle = OBALoc("on_demand.section_title", value: "On-demand service", comment: "Header of the stop page card listing dial-a-ride services that cover this stop")

    static let onDemandWhenHeader = OBALoc("on_demand.when_header", value: "When", comment: "Section header on the on-demand service page listing service days and hours")

    static let onDemandBookingHeader = OBALoc("on_demand.booking_header", value: "How to book", comment: "Section header on the on-demand service page with the booking deadline, phone number and links")

    static let onDemandBookByFormat = OBALoc("on_demand.book_by_fmt", value: "Book by %1$@ for a ride on %2$@", comment: "Booking deadline line. %1$@ is a formatted date and time (e.g. 'Today at 5:00 PM'), %2$@ is the travel date (e.g. 'Wed, Mar 11')")

    static let onDemandBookingOpensFormat = OBALoc("on_demand.booking_opens_fmt", value: "Booking opens %@", comment: "Shown when the next service day cannot be booked yet. %@ is a formatted date and time")

    static let onDemandNoNoticeRequired = OBALoc("on_demand.no_notice_required", value: "No advance booking required", comment: "Shown when a service can be booked at ride time")

    static let onDemandBookingClosed = OBALoc("on_demand.booking_closed", value: "Booking has closed for the upcoming service days", comment: "Shown when every upcoming service day's booking deadline has passed")

    static let onDemandCallFormat = OBALoc("on_demand.call_fmt", value: "Call %@", comment: "Button that dials the booking phone number. %@ is the phone number as published")

    static let onDemandBookOnline = OBALoc("on_demand.book_online", value: "Book online", comment: "Button that opens the agency's online booking page")

    static let onDemandMoreInfo = OBALoc("on_demand.more_info", value: "More information", comment: "Button that opens the agency's information page about the service")

    static let onDemandAllHours = OBALoc("on_demand.all_hours", value: "All service hours", comment: "Shown in place of a time window when a service runs all hours of its service days")

    // MARK: - Lists

    static let onDemandNoServices = OBALoc("on_demand.no_services", value: "No on-demand services", comment: "Empty state of the list of an agency's on-demand services")

    static let onDemandListTitle = OBALoc("on_demand.list_title", value: "On-demand services", comment: "Title of the list of an agency's on-demand services")

    static let agenciesOnDemandServices = OBALoc("agencies_controller.on_demand_services", value: "On-demand services", comment: "Action on the agency action sheet that opens the agency's on-demand services")

    // MARK: - Service kinds

    /// A short badge for the shape of a service (wiki §2.3).
    static func onDemandKindTitle(_ kind: ServiceKind) -> String {
        switch kind {
        case .zone:
            return OBALoc("on_demand.kind.zone", value: "Zone service", comment: "Badge for an on-demand service that serves anywhere inside one zone")
        case .zoneToZone:
            return OBALoc("on_demand.kind.zone_to_zone", value: "Zone to zone", comment: "Badge for an on-demand service that travels between zones")
        case .stopGroup:
            return OBALoc("on_demand.kind.stop_group", value: "Stop group", comment: "Badge for an on-demand service that serves a set of stops")
        case .deviatedRoute:
            return OBALoc("on_demand.kind.deviated_route", value: "Route deviation", comment: "Badge for a fixed route that can deviate into a zone on request")
        case .unknown:
            return OBALoc("on_demand.kind.unknown", value: "On-demand", comment: "Badge for an on-demand service of unknown shape")
        }
    }
}
