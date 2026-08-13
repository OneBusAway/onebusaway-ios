//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKitCore

struct UIColorWCAGTests {

    // MARK: - Relative luminance

    @Test func luminanceOfBlackIsZero() {
        #expect(abs(UIColor.black.wcagRelativeLuminance - 0.0) < 0.0001)
    }

    @Test func luminanceOfWhiteIsOne() {
        #expect(abs(UIColor.white.wcagRelativeLuminance - 1.0) < 0.0001)
    }

    // MARK: - Contrast ratio

    @Test func whiteOnBlackIs21ToOne() {
        #expect(abs(UIColor.white.wcagContrastRatio(against: .black) - 21.0) < 0.01)
    }

    @Test func ratioIsSymmetric() {
        let yellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        let a = UIColor.white.wcagContrastRatio(against: yellow)
        let b = yellow.wcagContrastRatio(against: .white)
        #expect(abs(a - b) < 0.0001)
    }

    /// #767676 is the canonical WCAG AA boundary gray: white text over it is
    /// almost exactly 4.5:1.
    @Test func whiteOn767676IsTheAABoundary() {
        let gray = UIColor(red: 118.0/255.0, green: 118.0/255.0, blue: 118.0/255.0, alpha: 1.0)
        let ratio = UIColor.white.wcagContrastRatio(against: gray)
        #expect(abs(ratio - 4.54) < 0.01)
    }

    // MARK: - Badge text color decision

    /// The reported bug: Metro's yellow with white text is ~1.8:1. The
    /// decision must reject white and return black (~11:1).
    @Test func metroYellowGetsBlackText() {
        let metroYellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        let chosen = metroYellow.badgeTextColor(preferring: .white, minimumRatio: 4.5)
        #expect(chosen == UIColor.black)
    }

    @Test func darkBlueKeepsAgencyWhiteText() {
        let darkBlue = UIColor(red: 0.05, green: 0.15, blue: 0.45, alpha: 1.0)
        let chosen = darkBlue.badgeTextColor(preferring: .white, minimumRatio: 4.5)
        #expect(chosen == UIColor.white)
    }

    @Test func nilPreferredComputesBlackOrWhite() {
        let metroYellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        #expect(metroYellow.badgeTextColor(preferring: nil, minimumRatio: 4.5) == UIColor.black)

        let darkBlue = UIColor(red: 0.05, green: 0.15, blue: 0.45, alpha: 1.0)
        #expect(darkBlue.badgeTextColor(preferring: nil, minimumRatio: 4.5) == UIColor.white)
    }

    /// A preferred color passing 4.5 but failing 7.0 must be rejected at the
    /// Increase Contrast threshold. White on #767676 is ~4.54:1.
    @Test func strictThresholdRejectsBorderlinePreferred() {
        let gray = UIColor(red: 118.0/255.0, green: 118.0/255.0, blue: 118.0/255.0, alpha: 1.0)
        #expect(gray.badgeTextColor(preferring: .white, minimumRatio: 4.5) == UIColor.white)
        #expect(gray.badgeTextColor(preferring: .white, minimumRatio: 7.0) == UIColor.black)
    }

    /// #7F7F7F under the 7:1 tier: white ≈ 3.6:1, black ≈ 5.8:1 — neither
    /// clears the bar, so the decision must fall back to the better one.
    @Test func whenNothingClearsTheBarTheHigherContrastFallbackWins() {
        let midGray = UIColor(red: 127.0/255.0, green: 127.0/255.0, blue: 127.0/255.0, alpha: 1.0)
        #expect(midGray.badgeTextColor(preferring: .white, minimumRatio: 7.0) == UIColor.black)
    }

    // MARK: - ThemeColors on-time green (#599)

    /// Light-mode `departureOnTime` (#007300) must clear WCAG AA (4.5:1) against
    /// white — the solid capsule and tinted walk-pill both put white or green
    /// text on this color. Identity checks on `DepartureStatus` would pass for
    /// any ThemeColors value; this locks the actual contrast.
    @Test func `On time color meets WCAG AA in light mode`() {
        let light = ThemeColors.shared.departureOnTime.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light)
        )
        #expect(light.wcagContrastRatio(against: .white) >= 4.5)
    }

    // MARK: - departureOnTime trait resolution (#1255)

    @Test func departureOnTimeForDarkStyleMatchesSystemGreen() {
        let themes = ThemeColors()
        let resolved = themes.departureOnTime(for: .dark)
        let expected = UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(colorsMatch(resolved, expected))
    }

    @Test func departureOnTimeForLightStyleKeepsConfiguredGreen() {
        let themes = ThemeColors()
        let resolved = themes.departureOnTime(for: .light)
        let configured = UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00)
        #expect(colorsMatch(resolved, configured))
    }

    private func colorsMatch(_ a: UIColor, _ b: UIColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) < 0.01 && abs(ag - bg) < 0.01 && abs(ab - bb) < 0.01 && abs(aa - ba) < 0.01
    }
}
