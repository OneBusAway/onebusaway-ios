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
}
