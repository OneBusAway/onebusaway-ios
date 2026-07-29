import Testing
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class AlarmLeadTimeTests {
    @Test func `Request within range passes through`() {
        #expect(AlarmLeadTime.clamped(5, minutesUntilDeparture: 20) == 5)
    }

    @Test func `Clamps to maximum 15`() {
        #expect(AlarmLeadTime.clamped(30, minutesUntilDeparture: 60) == 15)
    }

    @Test func `Clamps to minimum 1`() {
        #expect(AlarmLeadTime.clamped(0, minutesUntilDeparture: 20) == 1)
    }

    @Test func `Capped below minutes until departure`() {
        // A buzz can't be scheduled for a moment that's already passed.
        #expect(AlarmLeadTime.clamped(10, minutesUntilDeparture: 4) == 3)
    }

    @Test func `Departure too soon returns nil`() {
        // Matches StopViewModel.canCreateAlarm: requires arrivalDepartureMinutes > 1.
        #expect(AlarmLeadTime.clamped(5, minutesUntilDeparture: 1) == nil)
        #expect(AlarmLeadTime.clamped(5, minutesUntilDeparture: 0) == nil)
    }
}
