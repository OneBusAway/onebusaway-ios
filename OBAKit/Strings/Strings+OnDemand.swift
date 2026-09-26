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

    // MARK: - Zone card (spec 3.3)

    static let onDemandCardEyebrow = OBALoc("on_demand.card.eyebrow", value: "On-demand service here", comment: "Eyebrow above the service name on the zone card shown when the rider is inside a zone")
    static let onDemandCardCallToBook = OBALoc("on_demand.card.call_to_book", value: "Call to Book", comment: "Primary button on the zone card that dials the booking phone number")
    static let onDemandCardDetails = OBALoc("on_demand.card.details", value: "Details", comment: "Secondary button on the zone card that opens the service page")
    static let onDemandCardMoreServicesFormat = OBALoc("on_demand.card.more_services", value: "%d more services here", comment: "Footer of the zone card when more than one service covers the rider. Plural forms live in Localizable.stringsdict; the value is only the not-found fallback.")

    // MARK: - Status (spec 2.8)

    static let onDemandStatusOpenUntilFormat = OBALoc("on_demand.status.open_until", value: "Open · until %@", comment: "Card and picker status while a service is running. %@ is the end time, e.g. 4:40 PM")
    static let onDemandStatusOpenNowUntilFormat = OBALoc("on_demand.status.open_now_until", value: "Open now · until %@", comment: "Service page status while a service is running. %@ is the end time")
    static let onDemandStatusOpen = OBALoc("on_demand.status.open", value: "Open", comment: "Status of a service that runs continuously")
    static let onDemandStatusOpensFormat = OBALoc("on_demand.status.opens", value: "Opens %@", comment: "Status of a service not running yet. %@ is a relative day and time, e.g. 'tomorrow at 7:20 AM'")
    static let onDemandStatusBookByFormat = OBALoc("on_demand.status.book_by", value: "Book by %@", comment: "Short booking deadline for the card and bar. %@ is a relative day and time")
    static let onDemandStatusClosed = OBALoc("on_demand.status.closed", value: "Closed", comment: "Status of a service with no upcoming service day")

    // MARK: - Tags

    static let onDemandTagSameDay = OBALoc("on_demand.tag.same_day", value: "Same-day booking", comment: "Tag for a service booked the same day")
    static let onDemandTagAdvance = OBALoc("on_demand.tag.advance", value: "Advance booking", comment: "Tag for a service booked a day or more ahead")
    static let onDemandTagNoNotice = OBALoc("on_demand.tag.no_notice", value: "No notice needed", comment: "Tag for a service booked at ride time")
    static let onDemandTagEligibility = OBALoc("on_demand.tag.eligibility", value: "Eligibility required", comment: "Tag for a service that requires rider certification")

    // MARK: - Docked bar (spec 3.4)

    static let onDemandBarInside = OBALoc("on_demand.bar.inside", value: "Pickups available here", comment: "Bar title when the rider is inside a zone that is open now")

    /// One full sentence per compass point so translators can reorder freely.
    static func onDemandBarInsideNearEdgeFormat(_ direction: CompassDirection) -> String {
        switch direction {
        case .north: return OBALoc("on_demand.bar.inside_near_edge.north", value: "Inside · edge %@ north", comment: "Bar title near a zone edge. %@ is a distance")
        case .northeast: return OBALoc("on_demand.bar.inside_near_edge.northeast", value: "Inside · edge %@ northeast", comment: "Bar title near a zone edge. %@ is a distance")
        case .east: return OBALoc("on_demand.bar.inside_near_edge.east", value: "Inside · edge %@ east", comment: "Bar title near a zone edge. %@ is a distance")
        case .southeast: return OBALoc("on_demand.bar.inside_near_edge.southeast", value: "Inside · edge %@ southeast", comment: "Bar title near a zone edge. %@ is a distance")
        case .south: return OBALoc("on_demand.bar.inside_near_edge.south", value: "Inside · edge %@ south", comment: "Bar title near a zone edge. %@ is a distance")
        case .southwest: return OBALoc("on_demand.bar.inside_near_edge.southwest", value: "Inside · edge %@ southwest", comment: "Bar title near a zone edge. %@ is a distance")
        case .west: return OBALoc("on_demand.bar.inside_near_edge.west", value: "Inside · edge %@ west", comment: "Bar title near a zone edge. %@ is a distance")
        case .northwest: return OBALoc("on_demand.bar.inside_near_edge.northwest", value: "Inside · edge %@ northwest", comment: "Bar title near a zone edge. %@ is a distance")
        }
    }

    static func onDemandBarOutsideFormat(_ direction: CompassDirection) -> String {
        switch direction {
        case .north: return OBALoc("on_demand.bar.outside.north", value: "%@ north of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .northeast: return OBALoc("on_demand.bar.outside.northeast", value: "%@ northeast of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .east: return OBALoc("on_demand.bar.outside.east", value: "%@ east of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .southeast: return OBALoc("on_demand.bar.outside.southeast", value: "%@ southeast of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .south: return OBALoc("on_demand.bar.outside.south", value: "%@ south of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .southwest: return OBALoc("on_demand.bar.outside.southwest", value: "%@ southwest of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .west: return OBALoc("on_demand.bar.outside.west", value: "%@ west of the zone", comment: "Bar title outside a zone. %@ is a distance")
        case .northwest: return OBALoc("on_demand.bar.outside.northwest", value: "%@ northwest of the zone", comment: "Bar title outside a zone. %@ is a distance")
        }
    }

    static let onDemandBarBadgeFormat = OBALoc("on_demand.bar.badge", value: "%1$d of %2$d", comment: "Page badge on the docked bar thumbnail and the bar's accessibility value. %1$d is the page, %2$d the page count")
    static let onDemandBarShowEdge = OBALoc("on_demand.bar.a11y.show_edge", value: "Show nearest zone edge", comment: "Accessibility label of the bar's chevron when the rider is outside a zone")
    static let onDemandBarZoomOut = OBALoc("on_demand.bar.a11y.zoom_out", value: "Show whole zone", comment: "Accessibility label of the bar's thumbnail button")
    static let onDemandBarCallFormat = OBALoc("on_demand.bar.a11y.call", value: "Call %@", comment: "Accessibility label of the bar's phone button. %@ is the service name")
    static let onDemandBarMoreServices = OBALoc("on_demand.bar.a11y.more_services", value: "All services here", comment: "Accessibility action on the bar that opens the picker")

    // MARK: - Overlap picker (spec 3.5)

    static let onDemandPickerTitleFormat = OBALoc("on_demand.picker.title", value: "%d services here", comment: "Picker title for the services containing the probe point. Plural forms live in Localizable.stringsdict.")
    static let onDemandPickerTitleNearbyFormat = OBALoc("on_demand.picker.title_nearby", value: "%d services nearby", comment: "Picker title for every matched service. Plural forms live in Localizable.stringsdict.")
    static let onDemandPickerSubtitleLocationFormat = OBALoc("on_demand.picker.subtitle_location", value: "%@ · Your location", comment: "Picker subtitle. %@ is the locality of the rider's location")
    static let onDemandPickerSubtitleCenterFormat = OBALoc("on_demand.picker.subtitle_center", value: "%@ · Map center", comment: "Picker subtitle. %@ is the locality of the map centre")
    static let onDemandPickerSubtitlePointFormat = OBALoc("on_demand.picker.subtitle_point", value: "%@ · Selected place", comment: "Picker subtitle. %@ is the locality of a dropped pin or planner endpoint")
    static let onDemandPickerYourLocation = OBALoc("on_demand.picker.your_location", value: "Your location", comment: "Picker subtitle when no locality is known")
    static let onDemandPickerMapCenter = OBALoc("on_demand.picker.map_center", value: "Map center", comment: "Picker subtitle when no locality is known")
    static let onDemandPickerSelectedPlace = OBALoc("on_demand.picker.selected_place", value: "Selected place", comment: "Picker subtitle when no locality is known")
    static let onDemandPickerFooter = OBALoc("on_demand.picker.footer", value: "Sorted by soonest available.", comment: "Footer of the overlap picker")

    // MARK: - Service page (spec 3.6)

    static let onDemandDetailLocationInside = OBALoc("on_demand.detail.location_inside", value: "Your location is in this zone", comment: "Location row when the rider's location is inside the zone")
    static let onDemandDetailLocationOutside = OBALoc("on_demand.detail.location_outside", value: "Your location is outside this zone", comment: "Location row when the rider's location is outside the zone")
    static let onDemandDetailCenterInside = OBALoc("on_demand.detail.center_inside", value: "Map center is in this zone", comment: "Location row for the map centre")
    static let onDemandDetailCenterOutside = OBALoc("on_demand.detail.center_outside", value: "Map center is outside this zone", comment: "Location row for the map centre")
    static let onDemandDetailPointInside = OBALoc("on_demand.detail.point_inside", value: "This place is in this zone", comment: "Location row for a dropped pin or planner endpoint")
    static let onDemandDetailPointOutside = OBALoc("on_demand.detail.point_outside", value: "This place is outside this zone", comment: "Location row for a dropped pin or planner endpoint")
    static let onDemandDetailLocationSubFormat = OBALoc("on_demand.detail.location_sub", value: "Pickups available in %@", comment: "Sub line of the location row. %@ is a locality")
    static let onDemandDetailIncludesLocationFormat = OBALoc("on_demand.detail.includes_location", value: "%@ — includes your location", comment: "Service area sub line when the rider is inside. %@ is the area names")
    static let onDemandDetailWhereHeader = OBALoc("on_demand.detail.where_header", value: "Where", comment: "Section header listing service and drop-off areas")
    static let onDemandDetailServiceArea = OBALoc("on_demand.detail.service_area", value: "Service area", comment: "Row title for the pickup areas")
    static let onDemandDetailDropOff = OBALoc("on_demand.detail.drop_off", value: "Drop-off", comment: "Row title for the drop-off areas")
    static let onDemandDetailZoneCountFormat = OBALoc("on_demand.detail.zone_count", value: "%d zones", comment: "Fallback for unnamed areas. Plural forms live in Localizable.stringsdict.")
    static let onDemandDetailNoService = OBALoc("on_demand.detail.no_service", value: "No service", comment: "Hours column for weekdays without service")
    static let onDemandDetailOpenAgencyWebsite = OBALoc("on_demand.detail.open_agency_website", value: "Open Agency Website", comment: "Row that opens the service's url")

    // MARK: - Trip planner fallback (spec 3.8)

    static let onDemandPlannerSection = OBALoc("on_demand.planner.section", value: "On-demand options", comment: "Header of the planner fallback card")
    static let onDemandPlannerServesBoth = OBALoc("on_demand.planner.serves_both", value: "Serves both locations", comment: "First meta line of a qualifying planner fallback service")
    static let onDemandPlannerCaption = OBALoc("on_demand.planner.caption", value: "Services that need eligibility or cover only one end are hidden.", comment: "Caption under the planner fallback cards")
    static let onDemandPlannerShowAll = OBALoc("on_demand.planner.show_all", value: "Show all in the zone picker", comment: "Link under the planner fallback caption")
    static let onDemandPlannerEmpty = OBALoc("on_demand.planner.empty", value: "No on-demand service covers both locations.", comment: "Planner fallback when nothing qualifies and nothing is hidden")
    static let onDemandPlannerStatusNow = OBALoc("on_demand.planner.status_now", value: "Status shown for now.", comment: "Caption noting availability is evaluated at the current time")

    // MARK: - Address check (spec 3.7)

    static let onDemandAddressInsideFormat = OBALoc("on_demand.address.inside", value: "Inside %@", comment: "Map item line when the place is inside a zone. %@ is the service name")
    static let onDemandAddressInsideMoreFormat = OBALoc("on_demand.address.inside_more", value: "Inside %1$@ and %2$d more", comment: "Map item line when the place is inside several zones. %1$@ is the first service name, %2$d the count of others. Plural forms live in Localizable.stringsdict.")
    static let onDemandAddressOutsideFormat = OBALoc("on_demand.address.outside", value: "Outside %@", comment: "Map item line when the place is outside the nearest zone. %@ is the service name")

    // MARK: - Map layers sheet (spec 3.9)

    static let mapLayersGroupTransit = OBALoc("map_layers.group.transit", value: "Transit", comment: "Layers sheet group header")
    static let mapLayersGroupRentals = OBALoc("map_layers.group.rentals", value: "Rentals", comment: "Layers sheet group header")
    static let mapLayersStateOn = OBALoc("map_layers.state.on", value: "On", comment: "Layer tile subtitle when enabled")
    static let mapLayersStateOff = OBALoc("map_layers.state.off", value: "Off", comment: "Layer tile subtitle when disabled")
    static let mapLayersMinRange = OBALoc("map_layers.min_range", value: "Min. range", comment: "Label before the rental range chips")
}
