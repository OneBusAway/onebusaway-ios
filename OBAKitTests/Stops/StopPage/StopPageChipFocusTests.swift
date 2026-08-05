//
//  StopPageChipFocusTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopPageChipFocusTests {

    private func route(_ id: RouteID, live: Bool) -> StopRouteFocusModel.DrawnRoute {
        StopRouteFocusModel.DrawnRoute(
            routeID: id, shortName: id, color: .systemBlue, shapeID: "s", hasLiveVehicle: live
        )
    }

    @Test func `Chips preserve today's membership and alphabetical order`() {
        // Membership is stop.routes, unchanged — a route with nothing upcoming
        // keeps its chip, and the sheet matches the pushed page.
        let chips = RouteChip.chips(
            forRouteShortNames: ["62", "H", "40", ""],
            routeIDsByShortName: ["62": ["1_62"], "H": ["1_H"], "40": ["1_40"]]
        )
        #expect(chips.map(\.shortName) == ["40", "62", "H"])
    }

    @Test func `A chip carries every route ID sharing its short name`() {
        // Today's dedupe is by short name; preserve that visually while keeping
        // enough identity to focus one of them.
        let chips = RouteChip.chips(
            forRouteShortNames: ["40", "40"],
            routeIDsByShortName: ["40": ["1_40", "2_40"]]
        )
        #expect(chips.count == 1)
        #expect(Set(chips[0].routeIDs) == ["1_40", "2_40"])
    }

    @Test func `A chip is interactive only when the map drew its route with a vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_H", live: true), route("1_62", live: false)])

        let liveChip = RouteChip(shortName: "H", routeIDs: ["1_H"])
        let schedChip = RouteChip(shortName: "62", routeIDs: ["1_62"])
        let undrawnChip = RouteChip(shortName: "40", routeIDs: ["1_40"])

        #expect(liveChip.isInteractive(in: focus))
        #expect(!schedChip.isInteractive(in: focus))
        #expect(!undrawnChip.isInteractive(in: focus))
    }

    @Test func `Tapping a chip focuses the first of its routes with a vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_40", live: false), route("2_40", live: true)])
        let chip = RouteChip(shortName: "40", routeIDs: ["1_40", "2_40"])

        chip.toggleFocus(in: focus)

        #expect(focus.focusedRouteID == "2_40")
    }

    @Test func `Tapping an undrawn chip does nothing`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("1_H", live: true)])
        let chip = RouteChip(shortName: "40", routeIDs: ["1_40"])

        chip.toggleFocus(in: focus)

        #expect(focus.focusedRouteID == nil)
    }
}
