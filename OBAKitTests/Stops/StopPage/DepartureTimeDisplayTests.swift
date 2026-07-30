//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class DepartureTimeDisplayTests {

    private let formatters = Formatters(
        locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        themeColors: ThemeColors.shared
    )

    /// Deliberately aligned to :00 seconds. The same-minute and different-minute
    /// cases below reason about which clock minute an offset lands in, which is
    /// only predictable from a minute boundary.
    private let scheduled = Date(timeIntervalSinceReferenceDate: 699_999_960)

    private func display(expectedOffset: TimeInterval, isRealTime: Bool = true) -> DepartureTimeDisplay {
        DepartureTimeDisplay(
            scheduledDate: scheduled,
            expectedDate: scheduled.addingTimeInterval(expectedOffset),
            isRealTime: isRealTime,
            formatters: formatters
        )
    }

    private func formatted(_ offset: TimeInterval) -> String {
        formatters.timeFormatter.string(from: scheduled.addingTimeInterval(offset))
    }

    // MARK: - Which time is shown

    @Test func `No real time shows scheduled time alone with no strikethrough`() {
        // Without a prediction there is nothing to correct, so a struck-through
        // time would imply a change that never happened.
        let display = display(expectedOffset: 0, isRealTime: false)

        #expect(display.expectedTimeText == formatted(0))
        #expect(display.scheduledTimeText == nil)
    }

    @Test func `Late shows predicted time and strikes the scheduled one`() {
        let display = display(expectedOffset: 3 * 60)

        #expect(display.expectedTimeText == formatted(3 * 60))
        #expect(display.scheduledTimeText == formatted(0))
    }

    @Test func `Early shows predicted time and strikes the scheduled one`() {
        let display = display(expectedOffset: -4 * 60)

        #expect(display.expectedTimeText == formatted(-4 * 60))
        #expect(display.scheduledTimeText == formatted(0))
    }

    // MARK: - The "on time" band

    @Test func `Same minute shows one time only`() {
        // A 20 second deviation formats to the same clock minute; showing
        // "10:42 AM 10:42 AM" with one struck through would be nonsense.
        let display = display(expectedOffset: 20)

        #expect(display.expectedTimeText == formatted(0))
        #expect(display.scheduledTimeText == nil)
    }

    @Test func `Different minute inside on time band still shows both times`() {
        // scheduleStatus calls anything inside ±1.5 min "on time", but the rider
        // still needs the corrected clock time — this is the bug in issue #1214
        // that a "strike through only when late" rule would leave unfixed.
        let display = display(expectedOffset: 80)

        #expect(display.expectedTimeText == formatted(80))
        #expect(display.scheduledTimeText == formatted(0))
    }

    // MARK: - VoiceOver

    @Test func `Accessibility speaks both times when they differ`() {
        // Strikethrough is invisible to VoiceOver, so the correction has to be
        // carried by words.
        let display = display(expectedOffset: 3 * 60)

        #expect(display.accessibilityTimeDescription == "scheduled \(formatted(0)), now expected \(formatted(3 * 60))")
    }

    @Test func `Accessibility speaks one time when they match`() {
        let display = display(expectedOffset: 0, isRealTime: false)

        #expect(display.accessibilityTimeDescription == "at \(formatted(0))")
    }

    // MARK: - Model bridge

    @Test func `Init from arrival departure uses predicted time as expected`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predictedArrival: 1_700_000_180,
            predictedDeparture: 1_700_000_180
        )

        let display = DepartureTimeDisplay(arrivalDeparture: arrivalDeparture, formatters: formatters)

        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate))
        #expect(display.scheduledTimeText == formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
    }

    @Test func `Init from arrival departure ignores prediction when feed says not predicted`() throws {
        // A payload can carry predicted times while declaring `predicted: false`.
        // `arrivalDepartureDate` hands back the prediction anyway, so the display
        // has to gate on the flag or it would strike through a time the feed
        // just told us not to trust.
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predicted: false,
            predictedArrival: 1_700_000_180,
            predictedDeparture: 1_700_000_180
        )

        let display = DepartureTimeDisplay(arrivalDeparture: arrivalDeparture, formatters: formatters)

        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
        #expect(display.scheduledTimeText == nil)
    }

    @Test func `Init from arrival departure without prediction shows no strikethrough`() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture(predicted: false)

        let display = DepartureTimeDisplay(arrivalDeparture: arrivalDeparture, formatters: formatters)

        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
        #expect(display.scheduledTimeText == nil)
    }
}
