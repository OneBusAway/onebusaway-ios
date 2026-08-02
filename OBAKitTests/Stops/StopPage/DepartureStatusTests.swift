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

    /// #1255: SwiftUI must be able to force the dark provider so on-time green
    /// becomes systemGreen rather than the light-mode hex.
    @Test func `On time color for dark style matches system green`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        let resolved = status.color(for: .dark)
        let expected = UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(colorsMatch(resolved, expected))
    }

    @Test func `On time color for light style keeps high-contrast green`() {
        let status = DepartureStatus(isRealTime: true, scheduleStatus: .onTime, deviationMinutes: 0)
        let resolved = status.color(for: .light)
        let systemGreenLight = UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(!colorsMatch(resolved, systemGreenLight))
    }

    private func colorsMatch(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) < 0.01 && abs(ag - bg) < 0.01 && abs(ab - bb) < 0.01 && abs(aa - ba) < 0.01
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
