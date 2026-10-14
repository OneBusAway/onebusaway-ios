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
import UIKit
@testable import OBAKit

@Suite(.serialized)
@MainActor
struct MapStatusIndicatorTests {

    private func englishBundle() -> Bundle? {
        guard let path = Bundle(for: DonationCell.self).path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    // MARK: - Symbol Names

    @Test func `Compact symbol names match expected SF Symbols and resolve to valid system images`() {
        let cases: [(indicator: MapStatusIndicator, expectedName: String)] = [
            (.locationUnavailable, "location.slash"),
            (.preciseLocationUnavailable, "location.circle"),
            (.zoomInForStops, "plus.magnifyingglass"),
            (.zoomInForRentals, "plus.magnifyingglass")
        ]

        for (indicator, expectedName) in cases {
            #expect(indicator.symbolName == expectedName)
            #expect(UIImage(systemName: indicator.symbolName) != nil, "\(indicator) symbol '\(expectedName)' is not a valid SF Symbol")
        }
    }

    @Test func `Large accessibility symbol names match expected filled variants and resolve to valid system images`() {
        let cases: [(indicator: MapStatusIndicator, expectedName: String)] = [
            (.locationUnavailable, "location.slash.fill"),
            (.preciseLocationUnavailable, "location.circle.fill"),
            (.zoomInForStops, "plus.magnifyingglass"),
            (.zoomInForRentals, "plus.magnifyingglass")
        ]

        for (indicator, expectedName) in cases {
            #expect(indicator.largeSymbolName == expectedName)
            #expect(UIImage(systemName: indicator.largeSymbolName) != nil, "\(indicator) large symbol '\(expectedName)' is not a valid SF Symbol")
        }
    }

    // MARK: - Localized Text & String Catalog

    @Test func `Indicator localized text matches English string catalog`() throws {
        let bundle = try #require(englishBundle())
        let activeBundle = Bundle(for: DonationCell.self)

        let indicators: [(indicator: MapStatusIndicator, key: String, expectedEnglish: String)] = [
            (.locationUnavailable, "map_status_view.location_services_unavailable", "Location services unavailable"),
            (.preciseLocationUnavailable, "map_status_view.precise_location_unavailable", "Precise location unavailable"),
            (.zoomInForStops, "map_status_view.zoom_in_for_stops", "Zoom in for stops"),
            (.zoomInForRentals, "map_status_view.zoom_in_for_rentals", "Zoom in to see bikes and scooters")
        ]

        for (indicator, key, expectedEnglish) in indicators {
            let catalogString = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(catalogString != "MISSING", "\(key) is missing from the English catalog")
            #expect(catalogString == expectedEnglish, "\(key) has unexpected translation in English catalog")

            let activeString = activeBundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(indicator.localizedText == activeString, "\(indicator) localizedText did not match catalog translation for \(key)")
        }
    }
}
