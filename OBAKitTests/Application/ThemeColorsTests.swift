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

    /// White text and glyphs sit on this fill (walk chip, set alarm, Live
    /// Activity button). White on `departureOnTime` in dark mode is 2.0:1;
    /// the fill must clear AA text contrast in both appearances.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func `On time fill carries white text at AA contrast`(style: UIUserInterfaceStyle) {
        let fill = ThemeColors().departureOnTimeFill.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        #expect(UIColor.white.wcagContrastRatio(against: fill) >= 4.5)
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
        #expect(palette.warningText.wcagContrastRatio(against: palette.background) >= 4.5)
    }

    @Test func `The trait collection initializer still exists on iOS`() {
        let colors = ThemeColors(bundle: .main, traitCollection: UITraitCollection(userInterfaceStyle: .dark))
        #expect(colors.departureEarly == .systemRed)
    }

    /// The watch face is always dark and its `UIColor` has no dynamic colors,
    /// so every watch value must be fixed: identical under both styles.
    @Test func `Watch palette colors are fixed, not dynamic`() {
        let palette = ThemeColors.Palette.watch
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        for color in [palette.red, palette.blue, palette.green, palette.onTime, palette.onTimeFill, palette.gray,
                      palette.yellow, palette.warningText,
                      palette.label, palette.secondaryLabel, palette.separator, palette.fill,
                      palette.background, palette.secondaryBackground, palette.groupedBackground, palette.gray6] {
            #expect(color.resolvedColor(with: light) == color.resolvedColor(with: dark))
        }
    }

    @Test func `Watch palette is legible on black`() {
        let palette = ThemeColors.Palette.watch
        #expect(palette.label == .white)
        #expect(palette.background == .black)
    }
}
