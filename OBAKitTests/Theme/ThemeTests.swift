//
//  ThemeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore
import UIKit

@Suite(.serialized)
final class ThemeTests {

    @Test func `ThemeMetrics constants are correct`() {
        #expect(ThemeMetrics.accessibilityPadding == 16.0)
        #expect(ThemeMetrics.padding == 8.0)
        #expect(ThemeMetrics.compactPadding == 4.0)
        #expect(ThemeMetrics.ultraCompactPadding == 2.0)
        #expect(ThemeMetrics.cornerRadius == 8.0)
        #expect(ThemeMetrics.compactCornerRadius == 4.0)
    }

    @Test func `ThemeColors initializes successfully`() {
        let colors = ThemeColors.shared
        let normalLight = UITraitCollection {
            $0.accessibilityContrast = .normal
            $0.userInterfaceStyle = .light
        }

        #expect(colors.errorColor.resolvedColor(with: normalLight) == UIColor.systemRed.resolvedColor(with: normalLight))
        #expect(colors.departureEarly.resolvedColor(with: normalLight) == UIColor.systemRed.resolvedColor(with: normalLight))
        #expect(colors.departureLate.resolvedColor(with: normalLight) == UIColor.systemBlue.resolvedColor(with: normalLight))
        #expect(colors.departureUnknown == .label)
    }

    // MARK: - Integration: modified tokens are non-nil in both environments

    @Test func `Modified tokens are non-nil in normal and high-contrast environments`() {
        let colors = ThemeColors.shared
        let normal = UITraitCollection {
            $0.accessibilityContrast = .normal
            $0.userInterfaceStyle = .light
        }
        let highContrast = UITraitCollection {
            $0.accessibilityContrast = .high
            $0.userInterfaceStyle = .light
        }

        // Each modified token must resolve to a non-nil, non-clear color in both environments.
        let tokens: [(String, UIColor)] = [
            ("departureOnTime", colors.departureOnTime),
            ("departureOnTimeFill", colors.departureOnTimeFill),
            ("departureEarly", colors.departureEarly),
            ("departureLate", colors.departureLate),
            ("warningText", colors.warningText),
            ("brandAccent", colors.brandAccent),
            ("brandTint", colors.brandTint)
        ]

        for (name, token) in tokens {
            let normalResolved = token.resolvedColor(with: normal)
            let hcResolved = token.resolvedColor(with: highContrast)

            // Both must have alpha > 0 (non-clear)
            var alphaNormal: CGFloat = 0
            var alphaHC: CGFloat = 0
            normalResolved.getRed(nil, green: nil, blue: nil, alpha: &alphaNormal)
            hcResolved.getRed(nil, green: nil, blue: nil, alpha: &alphaHC)

            #expect(alphaNormal > 0, "\(name) normal mode resolved to clear/nil")
            #expect(alphaHC > 0, "\(name) high-contrast mode resolved to clear/nil")
        }
    }
}
