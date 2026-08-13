import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class DepartureStatusTests {

    @Test func `Scheduled only is gray with schedule data label`() {
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        #expect(status.color == UIColor.secondaryLabel)
        #expect(status.label == "schedule data")
        #expect(!status.showsOccupancy)
    }

    @Test func `Scheduled only never claims on time even with zero deviation`() {
        // §4.1: a scheduled bus is NOT "on time" — we have no idea if it's on time.
        let status = DepartureStatus(isRealTime: false, scheduleStatus: .unknown, deviationMinutes: 0)
        #expect(status.label != "on time")
    }

    @Test func `On time is green`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        #expect(status.color == ThemeColors.shared.departureOnTime)
        #expect(status.label == "on time")
        #expect(status.showsOccupancy)
    }

    @Test func `Late is blue with minute count`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .delayed, deviationMinutes: 4)
        #expect(status.color == ThemeColors.shared.departureLate)
        #expect(status.label == "4 min late")
    }

    @Test func `Early is red with minute count`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .early, deviationMinutes: -3)
        #expect(status.color == ThemeColors.shared.departureEarly)
        #expect(status.label == "3 min early")
    }
}
