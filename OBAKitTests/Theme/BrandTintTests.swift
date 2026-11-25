//
//  BrandTintTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// MARK: - WCAG luminance helpers

/// Compute the relative luminance of a color (WCAG 2.1 §1.4.3).
private func relativeLuminance(of color: UIColor, in traits: UITraitCollection) -> CGFloat {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
    color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: nil)
    func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// Compute the WCAG contrast ratio between two colors in the given trait collection.
private func contrastRatio(_ c1: UIColor, _ c2: UIColor, traits: UITraitCollection) -> CGFloat {
    let l1 = relativeLuminance(of: c1, in: traits)
    let l2 = relativeLuminance(of: c2, in: traits)
    let hi = max(l1, l2), lo = min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)
}

/// The brand green, #78AA36, was the app-wide tint: every bar button, link,
/// switch and selected tab. On white it is 2.76:1, short of even the 3:1 that
/// controls need, so Done, Edit, Back and Delete All were hard to make out.
@MainActor
@Suite(.serialized)
final class BrandTintTests: OBATestCase {

    private static let appearances: [(String, UITraitCollection)] = [
        ("light", UITraitCollection(userInterfaceStyle: .light)),
        ("dark", UITraitCollection(userInterfaceStyle: .dark)),
        ("light, increased contrast", UITraitCollection { $0.userInterfaceStyle = .light; $0.accessibilityContrast = .high }),
        ("dark, increased contrast", UITraitCollection { $0.userInterfaceStyle = .dark; $0.accessibilityContrast = .high })
    ]

    private func hue(_ color: UIColor) -> CGFloat {
        var hue: CGFloat = 0
        color.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        return hue
    }

    @Test func `The tint meets AA text contrast on the app's backgrounds`() {
        let colors = ThemeColors.shared
        for (name, traits) in Self.appearances {
            let tint = colors.brandTint.resolvedColor(with: traits)
            for background in [UIColor.systemBackground, .systemGroupedBackground, .secondarySystemGroupedBackground] {
                let ratio = tint.wcagContrastRatio(against: background.resolvedColor(with: traits))
                #expect(ratio >= 4.5, "\(name): \(ratio):1")
            }
        }
    }

    /// White-label apps keep their own colour: the tint is the brand, darkened
    /// or lightened only as far as it has to be.
    @Test func `The tint is the brand's hue`() {
        let colors = ThemeColors.shared
        for (name, traits) in Self.appearances {
            let brand = colors.brand.resolvedColor(with: traits)
            let tint = colors.brandTint.resolvedColor(with: traits)
            #expect(abs(hue(brand) - hue(tint)) < 0.02, "\(name)")
        }
    }

    @Test func `A colour that already passes isn't changed`() {
        let navy = UIColor(red: 0, green: 0, blue: 0.4, alpha: 1)
        #expect(navy.adjusted(toContrast: 4.5, against: .white) == navy)
    }

    @Test func `A brand too pale to read on white is darkened enough`() {
        let yellow = UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        let adjusted = yellow.adjusted(toContrast: 4.5, against: .white)
        #expect(adjusted.wcagContrastRatio(against: .white) >= 4.5)
    }

    @Test func `Bars, buttons and switches are tinted with it`() throws {
        _ = buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: name))
        let light = UITraitCollection(userInterfaceStyle: .light)
        let expected = ThemeColors.shared.brandTint.resolvedColor(with: light)

        for tint in [UINavigationBar.appearance().tintColor, UITabBar.appearance().tintColor, UIButton.appearance().tintColor, UISwitch.appearance().onTintColor] {
            #expect(try #require(tint).resolvedColor(with: light) == expected)
        }
    }

    // MARK: - High-contrast departure color tests (WCAG AAA ≥7:1)

    private static let highContrastLight = UITraitCollection {
        $0.accessibilityContrast = .high
        $0.userInterfaceStyle = .light
    }

    private static let highContrastDark = UITraitCollection {
        $0.accessibilityContrast = .high
        $0.userInterfaceStyle = .dark
    }

    @Test func `departureOnTime meets WCAG AAA in high contrast light mode`() {
        let color = ThemeColors.shared.departureOnTime
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "departureOnTime HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `departureOnTime meets WCAG AAA in high contrast dark mode`() {
        let color = ThemeColors.shared.departureOnTime
        let ratio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(ratio >= 7.0, "departureOnTime HC dark: \(ratio):1 (need ≥7.0)")
    }

    @Test func `departureEarly meets WCAG AAA in high contrast light mode`() {
        let color = ThemeColors.shared.departureEarly
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "departureEarly HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `departureEarly meets WCAG AAA in high contrast dark mode`() {
        let color = ThemeColors.shared.departureEarly
        let ratio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(ratio >= 7.0, "departureEarly HC dark: \(ratio):1 (need ≥7.0)")
    }

    @Test func `departureLate meets WCAG AAA in high contrast light mode`() {
        let color = ThemeColors.shared.departureLate
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "departureLate HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `departureLate meets WCAG AAA in high contrast dark mode`() {
        let color = ThemeColors.shared.departureLate
        let ratio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(ratio >= 7.0, "departureLate HC dark: \(ratio):1 (need ≥7.0)")
    }

    @Test func `warningText meets WCAG AAA in high contrast light mode`() {
        let color = ThemeColors.shared.warningText
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "warningText HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `warningText meets WCAG AAA in high contrast dark mode`() {
        let color = ThemeColors.shared.warningText
        let ratio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(ratio >= 7.0, "warningText HC dark: \(ratio):1 (need ≥7.0)")
    }

    @Test func `brandTint meets WCAG AAA in high contrast light mode`() {
        let color = ThemeColors.shared.brandTint
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "brandTint HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `brandTint meets WCAG AAA in high contrast dark mode`() {
        let color = ThemeColors.shared.brandTint
        let ratio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(ratio >= 7.0, "brandTint HC dark: \(ratio):1 (need ≥7.0)")
    }

    @Test func `brandAccent meets WCAG AAA on white and under white in high contrast light mode`() {
        let color = ThemeColors.shared.brandAccent
        let ratio = contrastRatio(color, .white, traits: Self.highContrastLight)
        #expect(ratio >= 7.0, "brandAccent HC light: \(ratio):1 (need ≥7.0)")
    }

    @Test func `brandAccent keeps AA contrast under white and on black in high contrast dark mode`() {
        let color = ThemeColors.shared.brandAccent
        let whiteRatio = contrastRatio(color, .white, traits: Self.highContrastDark)
        let blackRatio = contrastRatio(color, .black, traits: Self.highContrastDark)
        #expect(whiteRatio >= 4.5, "white on brandAccent HC dark: \(whiteRatio):1 (need ≥4.5)")
        #expect(blackRatio >= 4.5, "brandAccent on black HC dark: \(blackRatio):1 (need ≥4.5)")
    }

    @Test func `departureOnTimeFill meets WCAG AAA with white label in high contrast modes`() {
        let color = ThemeColors.shared.departureOnTimeFill
        let lightRatio = contrastRatio(color, .white, traits: Self.highContrastLight)
        let darkRatio = contrastRatio(color, .white, traits: Self.highContrastDark)
        #expect(lightRatio >= 7.0, "departureOnTimeFill HC light: \(lightRatio):1 (need ≥7.0)")
        #expect(darkRatio >= 7.0, "departureOnTimeFill HC dark: \(darkRatio):1 (need ≥7.0)")
    }
}
