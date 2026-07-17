import XCTest
@testable import OBAKit

@MainActor
final class AlarmLeadTimeTests: XCTestCase {
    func test_requestWithinRange_passesThrough() {
        XCTAssertEqual(AlarmLeadTime.clamped(5, minutesUntilDeparture: 20), 5)
    }

    func test_clampsToMaximum15() {
        XCTAssertEqual(AlarmLeadTime.clamped(30, minutesUntilDeparture: 60), 15)
    }

    func test_clampsToMinimum1() {
        XCTAssertEqual(AlarmLeadTime.clamped(0, minutesUntilDeparture: 20), 1)
    }

    func test_cappedBelowMinutesUntilDeparture() {
        // A buzz can't be scheduled for a moment that's already passed.
        XCTAssertEqual(AlarmLeadTime.clamped(10, minutesUntilDeparture: 4), 3)
    }

    func test_departureTooSoon_returnsNil() {
        // Matches StopViewModel.canCreateAlarm: requires arrivalDepartureMinutes > 1.
        XCTAssertNil(AlarmLeadTime.clamped(5, minutesUntilDeparture: 1))
        XCTAssertNil(AlarmLeadTime.clamped(5, minutesUntilDeparture: 0))
    }
}
