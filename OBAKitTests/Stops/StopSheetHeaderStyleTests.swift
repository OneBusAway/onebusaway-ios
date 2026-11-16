//
//  StopSheetHeaderStyleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
@testable import OBAKit
@testable import OBAKitCore

/// The stop sheet header's quieter look (#1754): colour only for data, and a
/// shape on everything tappable.
@Suite(.serialized)
struct StopSheetHeaderStyleTests {

    private func makeStop(code: String, direction: String?) throws -> Stop {
        var dict: [String: Any] = [
            "id": "1_\(code)",
            "code": code,
            "name": "Broadway E & E Harrison St",
            "lat": 47.6205,
            "lon": -122.3212,
            "locationType": 0,
            "routeIds": ["1_100"]
        ]
        if let direction { dict["direction"] = direction }
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    // MARK: - Subtitle

    @Test func `The subtitle is the stop number and direction, with a middle dot`() throws {
        let stop = try makeStop(code: "11190", direction: "N")
        #expect(StopSheetHeaderText.subtitle(for: stop) == "Stop 11190 · Northbound")
    }

    @Test func `The subtitle is just the number without a direction`() throws {
        let stop = try makeStop(code: "11190", direction: nil)
        #expect(StopSheetHeaderText.subtitle(for: stop) == "Stop 11190")
    }

    /// A non-numeric code keeps the core formatter's quoting.
    @Test func `A non-numeric code keeps its quotes`() throws {
        let stop = try makeStop(code: "Old Library", direction: "S")
        let subtitle = StopSheetHeaderText.subtitle(for: stop)
        #expect(subtitle.hasPrefix(Formatters.formattedStopCode(stop: stop)))
        #expect(subtitle.hasSuffix(" · Southbound"))
    }

    // MARK: - Walk and bike

    /// The icon says walk or bike, so the visible text is just the time. The
    /// spoken label keeps the mode.
    @Test func `Travel pills show minutes only and speak the mode`() {
        let info = WalkTimeInfo(walkMinutes: 123, distance: 9000)
        #expect(StopDirectionsPill.walk.shortText(for: info) == "123 min")
        #expect(StopDirectionsPill.bike.shortText(for: info) == "123 min")
        #expect(StopDirectionsPill.walk.text(for: info) == "123 min walk")
    }

    // MARK: - Past toggle

    @Test func `The past toggle counts earlier departures, pluralized`() {
        #expect(StopPageListHeaderRow.pastToggleTitle(count: 1, showPast: false) == "1 earlier")
        #expect(StopPageListHeaderRow.pastToggleTitle(count: 3, showPast: false) == "3 earlier")
        #expect(StopPageListHeaderRow.pastToggleTitle(count: 3, showPast: true) == "Hide past")
    }

    // MARK: - Route chips

    /// Selected reads without colour: an outline and heavier text.
    @Test func `A selected chip has an outline and heavier text`() {
        let selected = RouteChipAppearance(isSelected: true, isDimmed: false)
        let plain = RouteChipAppearance(isSelected: false, isDimmed: false)
        #expect(selected.strokeWidth == 1.5)
        #expect(plain.strokeWidth == 0)
        #expect(selected.fontWeight == .bold)
        #expect(plain.fontWeight == .semibold)
        #expect(selected.textOpacity == 1)
    }

    /// Unselected chips beside a selected one dim their text, not the whole
    /// chip, so the capsule keeps its shape and the text keeps its contrast.
    @Test func `Unselected chips dim their text to about 70 percent`() {
        let dimmed = RouteChipAppearance(isSelected: false, isDimmed: true)
        #expect(dimmed.textOpacity == 0.7)
        #expect(dimmed.strokeWidth == 0)
    }
}
