//
//  HomeExploreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The home sheet's Explore row: shortcuts to what the lists above don't hold.
@Suite
@MainActor
struct HomeExploreTests {

    @Test func `Nothing to offer, no items`() {
        #expect(HomeExploreItem.items(offersTripPlanning: false, rentalsEnabled: nil, alarmCount: 0).isEmpty)
    }

    /// A shortcut to a feature the region doesn't have would lead nowhere.
    @Test func `Each item appears only where it leads somewhere`() {
        #expect(HomeExploreItem.items(offersTripPlanning: true, rentalsEnabled: nil, alarmCount: 0) == [.planTrip])
        #expect(HomeExploreItem.items(offersTripPlanning: false, rentalsEnabled: false, alarmCount: 0) == [.rentals(isOn: false)])
        #expect(HomeExploreItem.items(offersTripPlanning: false, rentalsEnabled: nil, alarmCount: 2) == [.alarms(count: 2)])
    }

    @Test func `Items run Plan a Trip, Bikes and Scooters, Alarms`() {
        #expect(
            HomeExploreItem.items(offersTripPlanning: true, rentalsEnabled: true, alarmCount: 1)
                == [.planTrip, .rentals(isOn: true), .alarms(count: 1)]
        )
    }

    @Test func `Every item has a title and a symbol that exists`() {
        let items: [HomeExploreItem] = [.planTrip, .rentals(isOn: false), .rentals(isOn: true), .alarms(count: 3)]
        for item in items {
            #expect(!item.title.isEmpty)
            #expect(UIImage(systemName: item.systemImage) != nil)
        }
    }

    /// The layer's state changes, the tile doesn't move: one identity either way.
    @Test func `An item keeps its identity as its state changes`() {
        #expect(HomeExploreItem.rentals(isOn: true).id == HomeExploreItem.rentals(isOn: false).id)
        #expect(HomeExploreItem.alarms(count: 1).id == HomeExploreItem.alarms(count: 2).id)
        let ids = [HomeExploreItem.planTrip, .rentals(isOn: true), .alarms(count: 1)].map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// VoiceOver hears the count and the layer's state, which sighted riders
    /// get from the badge and the tile's fill.
    @Test func `Alarms and rentals speak their state`() {
        #expect(HomeExploreItem.planTrip.accessibilityValue == nil)
        #expect(HomeExploreItem.alarms(count: 2).accessibilityValue == "2")
        #expect(HomeExploreItem.rentals(isOn: true).accessibilityValue == Strings.mapLayersStateOn)
        #expect(HomeExploreItem.rentals(isOn: false).accessibilityValue == Strings.mapLayersStateOff)
    }
}
