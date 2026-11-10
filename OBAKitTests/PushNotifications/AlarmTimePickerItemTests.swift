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

    // MARK: - Track on Lock Screen

    private func trackSwitch(_ item: AlarmTimePickerItem) throws -> UISwitch {
        let views = try #require(item.makeViewsUnderDescription(with: BLTNInterfaceBuilder(appearance: item.appearance)))
        return try #require(views.lazy.compactMap { Self.firstSwitch(in: $0) }.first)
    }

    /// `AlarmBuilder.trackOnLockScreen` reads this when the rider confirms, to decide
    /// whether to start a Live Activity.
    @Test func `Turning Track on Lock Screen off is what the alarm sees, and the next picker remembers it`() throws {
        let departure = try departure(minutesAway: 30)
        let item = AlarmTimePickerItem(arrivalDeparture: departure, initialMinutes: 5, userDefaults: userDefaults)
        let toggle = try trackSwitch(item)
        let trackedBefore = item.trackOnLockScreen
        #expect(toggle.isOn)
        #expect(trackedBefore)

        toggle.isOn = false
        toggle.sendActions(for: .valueChanged)

        let trackedAfter = item.trackOnLockScreen
        let nextToggle = try trackSwitch(AlarmTimePickerItem(arrivalDeparture: departure, initialMinutes: 5, userDefaults: userDefaults))
        #expect(!trackedAfter)
        #expect(!nextToggle.isOn)
    }

    // MARK: - Lead times

    /// A departure `minutesAway` from now, plus 30 seconds so the whole-minute count
    /// doesn't slip while the test runs. It has no references, so its `trip` is nil:
    /// keep pickers and managers out of `#expect`, whose failure output would print
    /// the departure and trap on that nil.
    private func departure(minutesAway: Int) throws -> ArrivalDeparture {
        // `Fixtures.arrivalDeparture` takes seconds since the 2001 reference date.
        let time = Int(Date().timeIntervalSinceReferenceDate) + minutesAway * 60 + 30
        return try Fixtures.arrivalDeparture(predicted: false, scheduledArrival: time, scheduledDeparture: time)
    }

    private func leadTimes(_ manager: AlarmTimePickerManager) -> [String?] {
        let rows = manager.pickerView(manager.pickerView, numberOfRowsInComponent: 0)
        return (0..<rows).map { manager.pickerView(manager.pickerView, titleForRow: $0, forComponent: 0) }
    }

    @Test func `Lead times count down by fives, then by ones under ten minutes`() throws {
        let manager = AlarmTimePickerManager(arrivalDeparture: try departure(minutesAway: 30), initialMinutes: 5)

        let times = leadTimes(manager)

        #expect(times == [
            "25 minutes", "20 minutes", "15 minutes", "10 minutes", "9 minutes", "8 minutes", "7 minutes",
            "6 minutes", "5 minutes", "4 minutes", "3 minutes", "2 minutes", "1 minute"
        ])
    }

    @Test func `Lead times for a far-off departure step by half hours past two hours, then by quarter hours`() throws {
        let manager = AlarmTimePickerManager(arrivalDeparture: try departure(minutesAway: 200), initialMinutes: 5)

        let times = leadTimes(manager)

        #expect(Array(times.prefix(6)) == ["180 minutes", "150 minutes", "120 minutes", "105 minutes", "90 minutes", "75 minutes"])
    }

    @Test func `The picker starts on the requested lead time`() throws {
        let manager = AlarmTimePickerManager(arrivalDeparture: try departure(minutesAway: 30), initialMinutes: 10)

        manager.prepareForDisplay()
        let selected = manager.selectedMinutes

        #expect(selected == 10)
    }

    /// The change-alarm flow passes the current alarm's lead time, which an older
    /// departure time may have put between two steps.
    @Test func `A lead time between steps starts the picker on the closest step`() throws {
        let manager = AlarmTimePickerManager(arrivalDeparture: try departure(minutesAway: 30), initialMinutes: 12)

        manager.prepareForDisplay()
        let selected = manager.selectedMinutes

        #expect(selected == 10)
    }

    /// `AlarmBuilder` closes the bulletin without posting an alarm when this is nil.
    @Test func `A departure under two minutes away offers no lead time`() throws {
        let manager = AlarmTimePickerManager(arrivalDeparture: try departure(minutesAway: 1), initialMinutes: 5)

        manager.prepareForDisplay()
        let times = leadTimes(manager)
        let selected = manager.selectedMinutes

        #expect(times.isEmpty)
        #expect(selected == nil)
    }
}
