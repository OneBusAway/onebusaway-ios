//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore
@testable import OBAKit

@MainActor
final class DepartureTimeDisplayTests: XCTestCase {

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

    func test_noRealTime_showsScheduledTimeAloneWithNoStrikethrough() {
        // Without a prediction there is nothing to correct, so a struck-through
        // time would imply a change that never happened.
        let display = display(expectedOffset: 0, isRealTime: false)

        XCTAssertEqual(display.expectedTimeText, formatted(0))
        XCTAssertNil(display.scheduledTimeText)
    }

    func test_late_showsPredictedTimeAndStrikesTheScheduledOne() {
        let display = display(expectedOffset: 3 * 60)

        XCTAssertEqual(display.expectedTimeText, formatted(3 * 60))
        XCTAssertEqual(display.scheduledTimeText, formatted(0))
    }

    func test_early_showsPredictedTimeAndStrikesTheScheduledOne() {
        let display = display(expectedOffset: -4 * 60)

        XCTAssertEqual(display.expectedTimeText, formatted(-4 * 60))
        XCTAssertEqual(display.scheduledTimeText, formatted(0))
    }

    // MARK: - The "on time" band

    func test_sameMinute_showsOneTimeOnly() {
        // A 20 second deviation formats to the same clock minute; showing
        // "10:42 AM 10:42 AM" with one struck through would be nonsense.
        let display = display(expectedOffset: 20)

        XCTAssertEqual(display.expectedTimeText, formatted(0))
        XCTAssertNil(display.scheduledTimeText)
    }

    func test_differentMinuteInsideOnTimeBand_stillShowsBothTimes() {
        // scheduleStatus calls anything inside ±1.5 min "on time", but the rider
        // still needs the corrected clock time — this is the bug in issue #1214
        // that a "strike through only when late" rule would leave unfixed.
        let display = display(expectedOffset: 80)

        XCTAssertEqual(display.expectedTimeText, formatted(80))
        XCTAssertEqual(display.scheduledTimeText, formatted(0))
    }

    // MARK: - VoiceOver

    func test_accessibility_speaksBothTimesWhenTheyDiffer() {
        // Strikethrough is invisible to VoiceOver, so the correction has to be
        // carried by words.
        let display = display(expectedOffset: 3 * 60)

        XCTAssertEqual(
            display.accessibilityTimeDescription,
            "scheduled \(formatted(0)), now expected \(formatted(3 * 60))"
        )
    }

    func test_accessibility_speaksOneTimeWhenTheyMatch() {
        let display = display(expectedOffset: 0, isRealTime: false)

        XCTAssertEqual(display.accessibilityTimeDescription, "at \(formatted(0))")
    }

    // MARK: - Model bridge

    func test_initFromArrivalDeparture_usesPredictedTimeAsExpected() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture(
            predictedArrival: 1_700_000_180,
            predictedDeparture: 1_700_000_180
        )

        let display = DepartureTimeDisplay(arrivalDeparture: arrivalDeparture, formatters: formatters)

        XCTAssertEqual(display.expectedTimeText, formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate))
        XCTAssertEqual(display.scheduledTimeText, formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
    }

    func test_initFromArrivalDeparture_ignoresPredictionWhenFeedSaysNotPredicted() throws {
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

        XCTAssertEqual(display.expectedTimeText, formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
        XCTAssertNil(display.scheduledTimeText)
    }

    func test_initFromArrivalDeparture_withoutPrediction_showsNoStrikethrough() throws {
        let arrivalDeparture = try Fixtures.arrivalDeparture(predicted: false)

        let display = DepartureTimeDisplay(arrivalDeparture: arrivalDeparture, formatters: formatters)

        XCTAssertEqual(display.expectedTimeText, formatters.timeFormatter.string(from: arrivalDeparture.scheduledDate))
        XCTAssertNil(display.scheduledTimeText)
    }
}
