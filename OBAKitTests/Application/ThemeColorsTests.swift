//
//  ThemeColorsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite struct ThemeColorsTests {

    /// The split must not move a single iOS color in normal contrast mode.
    @Test func `iOS colors are unchanged by the palette split`() {
        let colors = ThemeColors()
        let normalLight = UITraitCollection { $0.userInterfaceStyle = .light; $0.accessibilityContrast = .normal }
        let normalDark = UITraitCollection { $0.userInterfaceStyle = .dark; $0.accessibilityContrast = .normal }

        for traits in [normalLight, normalDark] {
            #expect(colors.departureEarly.resolvedColor(with: traits) == UIColor.systemRed.resolvedColor(with: traits))
            #expect(colors.departureLate.resolvedColor(with: traits) == UIColor.systemBlue.resolvedColor(with: traits))
            #expect(colors.blue.resolvedColor(with: traits) == UIColor.systemBlue.resolvedColor(with: traits))
            #expect(colors.stopArrowFillColor.resolvedColor(with: traits) == UIColor.systemRed.resolvedColor(with: traits))
            #expect(colors.errorColor.resolvedColor(with: traits) == UIColor.systemRed.resolvedColor(with: traits))
        }

        #expect(colors.departureUnknown == .label)
        #expect(colors.departureUnknownBackground == .systemGray)
        #expect(colors.gray == .systemGray)
        #expect(colors.green == .systemGreen)
        #expect(colors.groupedTableBackground == .systemGroupedBackground)
        #expect(colors.groupedTableRowBackground == .white)
        #expect(colors.systemBackground == .systemBackground)
        #expect(colors.label == .label)
        #expect(colors.secondaryLabel == .secondaryLabel)
        #expect(colors.separator == .separator)
        #expect(colors.highlightedBackgroundColor == .systemFill)
        #expect(colors.secondaryBackgroundColor == .secondarySystemBackground)
        #expect(colors.propertyChanged == .systemYellow)
        #expect(colors.stopAnnotationFillColor == .systemGray6)
        #expect(colors.stopAnnotationStrokeColor == .darkGray)
        #expect(colors.systemFill == .systemFill)
        #expect(colors.lightText == .white)
    }

    @Test func `On time color is dark green in light mode and system green in dark mode`() {
        let colors = ThemeColors()
        let light = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        #expect(light == UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00))
        #expect(dark == UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(colors.departureOnTimeBackground == colors.departureOnTimeFill)
    }

    /// White text and glyphs sit on this fill (walk chip, set alarm, Live
    /// Activity button). White on `departureOnTime` in dark mode is 2.0:1;
    /// the fill must clear AA text contrast in both appearances.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `On time fill carries white text at AA contrast`(style: UIUserInterfaceStyle) {
        let fill = ThemeColors().departureOnTimeFill.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        #expect(UIColor.white.wcagContrastRatio(against: fill) >= 4.5)
    }

    /// Departure badges (`DepartureTimeBadge` and the widget's
    /// `DepartureTimeBadgeView`) render white text over
    /// `backgroundColorForScheduleStatus`, so every real-time fill must clear
    /// WCAG AA contrast under white in both appearances.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `Departure badge backgrounds carry white text at AA contrast`(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors())

        for status in [ScheduleStatus.onTime, .early, .delayed] {
            let fill = formatters.backgroundColorForScheduleStatus(status).resolvedColor(with: traits)
            let ratio = UIColor.white.wcagContrastRatio(against: fill)
            #expect(ratio >= 4.5, "\(status) in \(style == .dark ? "dark" : "light") mode: \(ratio):1")
            #expect(!fill.isLightColor, "\(status) in \(style == .dark ? "dark" : "light") mode should keep white badge text")
        }
    }

    /// Warning text (service alerts, a stale Live Activity) on the page
    /// background. `systemOrange` on white is 2.2:1.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `Warning text clears AA contrast on the system background`(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let text = ThemeColors().warningText.resolvedColor(with: traits)
        let background = UIColor.systemBackground.resolvedColor(with: traits)
        #expect(text.wcagContrastRatio(against: background) >= 4.5)
    }

    @Test func `Watch fill and warning colors clear AA on their backgrounds`() {
        let palette = ThemeColors.Palette.watch
        #expect(UIColor.white.wcagContrastRatio(against: palette.onTimeFill) >= 4.5)
        #expect(UIColor.white.wcagContrastRatio(against: palette.earlyFill) >= 4.5)
        #expect(UIColor.white.wcagContrastRatio(against: palette.lateFill) >= 4.5)
        #expect(palette.warningText.wcagContrastRatio(against: palette.background) >= 4.5)
    }

    @Test func `The trait collection initializer still exists on iOS`() {
        let darkNormal = UITraitCollection { $0.userInterfaceStyle = .dark; $0.accessibilityContrast = .normal }
        let colors = ThemeColors(bundle: .main, traitCollection: darkNormal)
        #expect(colors.departureEarly.resolvedColor(with: darkNormal) == UIColor.systemRed.resolvedColor(with: darkNormal))
    }

    /// The eyebrow, "N more" link and planner links set the accent on the
    /// card's background, and the Call to Book pill sets white text on it.
    @Test(arguments: [UIAccessibilityContrast.normal, .high])
    func `Brand accent keeps 4.5 to 1 on the card and under white text in both styles`(contrast: UIAccessibilityContrast) {
        let accent = ThemeColors().brandAccent
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = contrast }
            let resolved = accent.resolvedColor(with: traits)
            let card = UIColor.systemBackground.resolvedColor(with: traits)
            #expect(resolved.wcagContrastRatio(against: card) >= 4.5, "accent on the \(style == .dark ? "dark" : "light") card (contrast: \(contrast.rawValue))")
            #expect(UIColor.white.wcagContrastRatio(against: resolved) >= 4.5, "white pill text in \(style == .dark ? "dark" : "light") mode (contrast: \(contrast.rawValue))")
        }
        let light = accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(light == UIColor(red: 0x48 / 255.0, green: 0x66 / 255.0, blue: 0x21 / 255.0, alpha: 1.0), "light mode keeps #486621")
    }

    /// The More header sets footnote-size `lightText` on its background, which
    /// is `brandAccent`: on `brand` it was 2.76:1 in the OneBusAway app.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `More header text clears AA on the brand accent`(style: UIUserInterfaceStyle) {
        let colors = ThemeColors()
        for contrast in [UIAccessibilityContrast.normal, .high] {
            let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.accessibilityContrast = contrast }
            let background = colors.brandAccent.resolvedColor(with: traits)
            #expect(colors.lightText.resolvedColor(with: traits).wcagContrastRatio(against: background) >= 4.5)
        }
    }

    /// The host app's `AccentColor` asset is the SwiftUI accent: tinted text
    /// and links on the page background, in every appearance. (Prominent
    /// buttons, which draw white on the fill, tint with `brandAccent` instead:
    /// no single dark-mode green clears 4.5:1 both against white and as text
    /// on the elevated dark backgrounds.) In light mode the accent is also the
    /// fill of any prominent button left untinted, so white must read on it.
    @Test(arguments: [UIAccessibilityContrast.normal, .high])
    func `Accent color clears AA as text and under white in light mode`(contrast: UIAccessibilityContrast) throws {
        let accent = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: nil), "the host app names an AccentColor")
        let traits = UITraitCollection { $0.userInterfaceStyle = .light; $0.accessibilityContrast = contrast }
        let resolved = accent.resolvedColor(with: traits)
        for background in [UIColor.systemBackground, .systemGroupedBackground] {
            #expect(resolved.wcagContrastRatio(against: background.resolvedColor(with: traits)) >= 4.5)
        }
        #expect(UIColor.white.wcagContrastRatio(against: resolved) >= 4.5)
    }

    @Test(arguments: [UIAccessibilityContrast.normal, .high])
    func `Accent color clears AA as text on dark backgrounds`(contrast: UIAccessibilityContrast) throws {
        let accent = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: nil), "the host app names an AccentColor")
        for level in [UIUserInterfaceLevel.base, .elevated] {
            let traits = UITraitCollection {
                $0.userInterfaceStyle = .dark
                $0.accessibilityContrast = contrast
                $0.userInterfaceLevel = level
            }
            let resolved = accent.resolvedColor(with: traits)
            for background in [UIColor.systemBackground, .secondarySystemBackground] {
                #expect(resolved.wcagContrastRatio(against: background.resolvedColor(with: traits)) >= 4.5,
                        "accent on \(background) at level \(level.rawValue)")
            }
        }
    }

    /// The watch face is always dark and its `UIColor` has no dynamic colors,
    /// so every watch value must be fixed: identical under both styles.
    @Test func `Watch palette colors are fixed, not dynamic`() {
        let palette = ThemeColors.Palette.watch
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for color in [palette.red, palette.blue, palette.green, palette.onTime, palette.onTimeFill,
                      palette.earlyFill, palette.lateFill, palette.gray,
                      palette.yellow, palette.warningText,
                      palette.label, palette.secondaryLabel, palette.separator, palette.fill,
                      palette.background, palette.secondaryBackground, palette.groupedBackground, palette.gray6,
                      palette.brandAccent] {
            #expect(color.resolvedColor(with: light) == color.resolvedColor(with: dark))
        }
    }

    @Test func `Watch palette is legible on black`() {
        let palette = ThemeColors.Palette.watch
        #expect(palette.label == .white)
        #expect(palette.background == .black)
    }
}
