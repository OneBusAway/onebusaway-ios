//
//  OnDemandStringsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The DRT copy catalogue (spec 2.8) is in the English table and its plurals resolve.
@MainActor
@Suite(.serialized)
final class OnDemandStringsTests {

    private static let keys = [
        "on_demand.card.eyebrow", "on_demand.card.call_to_book", "on_demand.card.details", "on_demand.card.more_services",
        "on_demand.status.open_until", "on_demand.status.open_now_until", "on_demand.status.open", "on_demand.status.opens", "on_demand.status.book_by", "on_demand.status.closed",
        "on_demand.tag.same_day", "on_demand.tag.advance", "on_demand.tag.no_notice", "on_demand.tag.eligibility",
        "on_demand.bar.inside", "on_demand.bar.badge", "on_demand.bar.a11y.show_edge", "on_demand.bar.a11y.zoom_out", "on_demand.bar.a11y.call", "on_demand.bar.a11y.more_services",
        "on_demand.picker.title", "on_demand.picker.title_nearby", "on_demand.picker.subtitle_location", "on_demand.picker.subtitle_center", "on_demand.picker.subtitle_point",
        "on_demand.picker.your_location", "on_demand.picker.map_center", "on_demand.picker.selected_place", "on_demand.picker.footer",
        "on_demand.detail.location_inside", "on_demand.detail.location_outside", "on_demand.detail.center_inside", "on_demand.detail.center_outside",
        "on_demand.detail.point_inside", "on_demand.detail.point_outside", "on_demand.detail.location_sub", "on_demand.detail.includes_location",
        "on_demand.detail.where_header", "on_demand.detail.service_area", "on_demand.detail.drop_off", "on_demand.detail.zone_count", "on_demand.detail.no_service", "on_demand.detail.open_agency_website",
        "on_demand.planner.section", "on_demand.planner.serves_both", "on_demand.planner.caption", "on_demand.planner.show_all", "on_demand.planner.empty", "on_demand.planner.status_now",
        "on_demand.address.inside", "on_demand.address.inside_more", "on_demand.address.outside",
        "map_layers.group.transit", "map_layers.group.rentals", "map_layers.state.on", "map_layers.state.off", "map_layers.min_range"
    ] + CompassDirection.allCases.flatMap { ["on_demand.bar.inside_near_edge.\($0.rawValue)", "on_demand.bar.outside.\($0.rawValue)"] }

    private var english: [String: String] {
        let bundle = Bundle(for: DonationCell.self)
        let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")!
        return NSDictionary(contentsOf: url) as! [String: String]
    }

    @Test func `Every on-demand key is in the English table`() {
        let table = english
        for key in Self.keys {
            #expect(table[key] != nil, "\(key)")
        }
    }

    @Test func `Plural keys resolve one and other forms`() {
        #expect(OnDemandCopy.moreServices(1) == "1 more service here")
        #expect(OnDemandCopy.moreServices(3) == "3 more services here")
        #expect(OnDemandCopy.pickerTitle(count: 1, nearby: false) == "1 service here")
        #expect(OnDemandCopy.pickerTitle(count: 2, nearby: true) == "2 services nearby")
        #expect(OnDemandCopy.zoneCount(1) == "1 zone")
        #expect(OnDemandCopy.zoneCount(4) == "4 zones")
        #expect(OnDemandCopy.addressInsideMore(name: "Dial-a-Ride", extra: 1) == "Inside Dial-a-Ride and 1 more")
    }
}
