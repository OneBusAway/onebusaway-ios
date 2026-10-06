//
//  LaunchRouteGateTests.swift
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

/// A white-label app can name a route in `OBAKitConfig.LaunchRouteID` so the map
/// opens on it. These tests pin the rules that keep that from ever getting in
/// the rider's way.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/617
@Suite(.serialized)
struct LaunchRouteGateTests {

    // MARK: - Config parsing

    @Test func `An absent config value disables the launch route`() {
        var gate = LaunchRouteGate(configValue: nil)

        #expect(gate.routeID == nil)
        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == nil)
    }

    @Test func `A blank config value disables the launch route`() {
        var gate = LaunchRouteGate(configValue: "  \n ")

        #expect(gate.routeID == nil)
        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == nil)
    }

    @Test func `Surrounding whitespace is trimmed from the route ID`() {
        let gate = LaunchRouteGate(configValue: " 1_100479\n")

        #expect(gate.routeID == "1_100479")
    }

    // MARK: - Claiming

    @Test func `The route is claimed once a region is available`() {
        var gate = LaunchRouteGate(configValue: "1_100479")

        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == "1_100479")
        #expect(gate.isClaimed)
    }

    @Test func `The route is claimed only once per launch`() {
        var gate = LaunchRouteGate(configValue: "1_100479")

        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == nil)
    }

    @Test func `Without a region the claim waits rather than giving up`() {
        var gate = LaunchRouteGate(configValue: "1_100479")

        #expect(gate.claim(regionIdentifier: nil, hasPendingNavigation: false) == nil)
        #expect(!gate.isClaimed)
        #expect(!gate.isSuppressed)
        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == "1_100479")
    }

    @Test func `A deep link received before the claim suppresses the route`() {
        var gate = LaunchRouteGate(configValue: "1_100479")

        gate.suppress()

        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == nil)
    }

    @Test func `A pending stop navigation suppresses the route for the rest of the launch`() {
        var gate = LaunchRouteGate(configValue: "1_100479")

        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: true) == nil)
        #expect(gate.isSuppressed)
        #expect(gate.claim(regionIdentifier: 1, hasPendingNavigation: false) == nil)
    }

    // MARK: - Displaying

    @Test func `A claimed route with geometry on an idle map may be displayed`() {
        var gate = LaunchRouteGate(configValue: "1_100479")
        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        #expect(gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: false, regionIdentifier: 1))
    }

    @Test func `An unclaimed route is never displayed`() {
        let gate = LaunchRouteGate(configValue: "1_100479")

        #expect(!gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: false, regionIdentifier: 1))
    }

    @Test func `A deep link that arrives while the route loads wins`() {
        var gate = LaunchRouteGate(configValue: "1_100479")
        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        gate.suppress()

        #expect(!gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: false, regionIdentifier: 1))
    }

    @Test func `A route the rider has already replaced on the map is not displayed`() {
        var gate = LaunchRouteGate(configValue: "1_100479")
        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        #expect(!gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: true, regionIdentifier: 1))
    }

    @Test func `A route with no polylines is not displayed`() {
        var gate = LaunchRouteGate(configValue: "1_100479")
        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        #expect(!gate.mayDisplay(polylineCount: 0, isMapShowingOtherContent: false, regionIdentifier: 1))
    }

    @Test func `A route loaded for a region the rider has since left is not displayed`() {
        var gate = LaunchRouteGate(configValue: "1_100479")
        _ = gate.claim(regionIdentifier: 1, hasPendingNavigation: false)

        #expect(!gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: false, regionIdentifier: 2))
        #expect(!gate.mayDisplay(polylineCount: 2, isMapShowingOtherContent: false, regionIdentifier: nil))
    }
}
