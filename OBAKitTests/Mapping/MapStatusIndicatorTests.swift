//
//  MapStatusIndicatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

@Suite(.serialized)
@MainActor
struct MapStatusIndicatorTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Symbol Names

    @Test func `Compact symbol names match expected SF Symbols`() {
        #expect(MapStatusIndicator.locationUnavailable.symbolName == "location.slash")
        #expect(MapStatusIndicator.preciseLocationUnavailable.symbolName == "location.circle")
        #expect(MapStatusIndicator.zoomInForStops.symbolName == "plus.magnifyingglass")
        #expect(MapStatusIndicator.zoomInForRentals.symbolName == "plus.magnifyingglass")
    }

    @Test func `Large accessibility symbol names match expected filled variants`() {
        #expect(MapStatusIndicator.locationUnavailable.largeSymbolName == "location.slash.fill")
        #expect(MapStatusIndicator.preciseLocationUnavailable.largeSymbolName == "location.circle.fill")
        #expect(MapStatusIndicator.zoomInForStops.largeSymbolName == "plus.magnifyingglass")
        #expect(MapStatusIndicator.zoomInForRentals.largeSymbolName == "plus.magnifyingglass")
    }

    // MARK: - Localized Text

    @Test func `Localized text returns expected strings for each indicator state`() {
        #expect(MapStatusIndicator.locationUnavailable.localizedText == "Location services unavailable")
        #expect(MapStatusIndicator.preciseLocationUnavailable.localizedText == "Precise location unavailable")
        #expect(MapStatusIndicator.zoomInForStops.localizedText == "Zoom in for stops")
        #expect(MapStatusIndicator.zoomInForRentals.localizedText == "Zoom in to see bikes and scooters")
    }

    // MARK: - String Catalog Integrity

    @Test func `Localization keys exist in the English string bundle`() throws {
        let bundle = try #require(englishBundle())

        let keys = [
            "map_status_view.location_services_unavailable": "Location services unavailable",
            "map_status_view.precise_location_unavailable": "Precise location unavailable",
            "map_status_view.zoom_in_for_stops": "Zoom in for stops",
            "map_status_view.zoom_in_for_rentals": "Zoom in to see bikes and scooters"
        ]

        for (key, expectedValue) in keys {
            let localized = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(localized != "MISSING", "\(key) is missing from the English catalog")
            #expect(localized == expectedValue, "\(key) has unexpected translation in English catalog")
        }
    }
}
