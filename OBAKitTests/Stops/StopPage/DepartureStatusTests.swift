import XCTest
import OBAKitCore
@testable import OBAKit

@MainActor
final class DepartureStatusTests: XCTestCase {

    func test_scheduledOnly_isGrayWithScheduleDataLabel() {
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        XCTAssertEqual(status.color, UIColor.secondaryLabel)
        XCTAssertEqual(status.label, "schedule data")
        XCTAssertFalse(status.showsOccupancy)
    }

    func test_scheduledOnly_neverClaimsOnTime_evenWithZeroDeviation() {
        // §4.1: a scheduled bus is NOT "on time" — we have no idea if it's on time.
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        XCTAssertNotEqual(status.label, "on time")
    }

    func test_onTime_isGreen() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        XCTAssertEqual(status.color, ThemeColors.shared.departureOnTime)
        XCTAssertEqual(status.label, "on time")
        XCTAssertTrue(status.showsOccupancy)
    }

    func test_late_isBlue_withMinuteCount() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 4)
        XCTAssertEqual(status.color, ThemeColors.shared.departureLate)
        XCTAssertEqual(status.label, "4 min late")
    }

    func test_early_isRed_withMinuteCount() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .early, deviationMinutes: -3)
        XCTAssertEqual(status.color, ThemeColors.shared.departureEarly)
        XCTAssertEqual(status.label, "3 min early")
    }
}
