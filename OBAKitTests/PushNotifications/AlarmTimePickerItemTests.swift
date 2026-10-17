//
//  AlarmTimePickerItemTests.swift
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
final class AlarmTimePickerItemTests: OBATestCase {

    /// The switch read "Switch button, on" with no name. It's on by default and
    /// starts a Live Activity, so a VoiceOver rider needs to know what it is.
    @Test func `The Track on Lock Screen switch is named`() throws {
        let departure = try #require(Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures_1_1121.json").arrivalsAndDepartures.first)
        let item = AlarmTimePickerItem(arrivalDeparture: departure, initialMinutes: 5, userDefaults: userDefaults)
        let views = try #require(item.makeViewsUnderDescription(with: BLTNInterfaceBuilder(appearance: item.appearance)))

        let toggle = try #require(views.lazy.compactMap { Self.firstSwitch(in: $0) }.first)
        #expect(toggle.accessibilityLabel == OBALoc("alarm_time_picker.track_on_lock_screen", value: "Track on Lock Screen", comment: ""))
    }

    private static func firstSwitch(in view: UIView) -> UISwitch? {
        if let toggle = view as? UISwitch { return toggle }
        return view.subviews.lazy.compactMap { firstSwitch(in: $0) }.first
    }
}
