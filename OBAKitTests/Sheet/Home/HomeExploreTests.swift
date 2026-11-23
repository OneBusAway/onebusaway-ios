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
        #expect(HomeExploreItem.items(offersTripPlanning: false, rentalsEnabled: nil).isEmpty)
    }

    /// A shortcut to a feature the region doesn't have would lead nowhere.
    @Test func `Each item appears only where it leads somewhere`() {
        #expect(HomeExploreItem.items(offersTripPlanning: true, rentalsEnabled: nil) == [.planTrip])
        #expect(HomeExploreItem.items(offersTripPlanning: false, rentalsEnabled: false) == [.rentals(isOn: false)])
    }

    @Test func `Items run Plan a Trip, then Bikes and Scooters`() {
        #expect(
            HomeExploreItem.items(offersTripPlanning: true, rentalsEnabled: true)
                == [.planTrip, .rentals(isOn: true)]
        )
    }

    @Test func `Every item has a title and a symbol that exists`() {
        let items: [HomeExploreItem] = [.planTrip, .rentals(isOn: false), .rentals(isOn: true)]
        for item in items {
            #expect(!item.title.isEmpty)
            #expect(UIImage(systemName: item.systemImage) != nil)
        }
    }

    /// The layer's state changes, the tile doesn't move: one identity either way.
    @Test func `An item keeps its identity as its state changes`() {
        #expect(HomeExploreItem.rentals(isOn: true).id == HomeExploreItem.rentals(isOn: false).id)
        #expect(HomeExploreItem.planTrip.id != HomeExploreItem.rentals(isOn: true).id)
    }

    /// VoiceOver hears the layer's state, which sighted riders get from the
    /// tile's fill.
    @Test func `Rentals speak their state`() {
        #expect(HomeExploreItem.planTrip.accessibilityValue == nil)
        #expect(HomeExploreItem.rentals(isOn: true).accessibilityValue == Strings.mapLayersStateOn)
        #expect(HomeExploreItem.rentals(isOn: false).accessibilityValue == Strings.mapLayersStateOff)
    }
}
