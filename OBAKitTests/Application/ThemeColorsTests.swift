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

    /// The split must not move a single iOS color.
    @Test func `iOS colors are unchanged by the palette split`() {
        let colors = ThemeColors()

        #expect(colors.departureEarly == .systemRed)
        #expect(colors.departureEarlyBackground == .systemRed)
        #expect(colors.departureLate == .systemBlue)
        #expect(colors.departureLateBackground == .systemBlue)
        #expect(colors.departureUnknown == .label)
        #expect(colors.departureUnknownBackground == .systemGray)
        #expect(colors.gray == .systemGray)
        #expect(colors.green == .systemGreen)
        #expect(colors.blue == .systemBlue)
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
        #expect(colors.stopArrowFillColor == .systemRed)
        #expect(colors.systemFill == .systemFill)
        #expect(colors.lightText == .white)
        #expect(colors.errorColor == .systemRed)
    }

    @Test func `On time color is dark green in light mode and system green in dark mode`() {
        let colors = ThemeColors()
        let light = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = colors.departureOnTime.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        #expect(light == UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00))
        #expect(dark == UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(colors.departureOnTimeBackground == colors.departureOnTime)
    }

    @Test func `The trait collection initializer still exists on iOS`() {
        let colors = ThemeColors(bundle: .main, traitCollection: UITraitCollection(userInterfaceStyle: .dark))
        #expect(colors.departureEarly == .systemRed)
    }

    /// The eyebrow, "N more" link and planner links set the accent on the
    /// card's background, and the Call to Book pill sets white text on it.
    @Test func `Brand accent keeps 4.5 to 1 on the card and under white text in both styles`() {
        let accent = ThemeColors().brandAccent
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let resolved = accent.resolvedColor(with: traits)
            let card = UIColor.systemBackground.resolvedColor(with: traits)
            #expect(resolved.wcagContrastRatio(against: card) >= 4.5, "accent on the \(style == .dark ? "dark" : "light") card")
            #expect(UIColor.white.wcagContrastRatio(against: resolved) >= 4.5, "white pill text in \(style == .dark ? "dark" : "light") mode")
        }
        let light = accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(light == UIColor(red: 0x48 / 255.0, green: 0x66 / 255.0, blue: 0x21 / 255.0, alpha: 1.0), "light mode keeps #486621")
    }

    /// The watch face is always dark and its `UIColor` has no dynamic colors,
    /// so every watch value must be fixed: identical under both styles.
    @Test func `Watch palette colors are fixed, not dynamic`() {
        let palette = ThemeColors.Palette.watch
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for color in [palette.red, palette.blue, palette.green, palette.onTime, palette.gray, palette.yellow,
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
