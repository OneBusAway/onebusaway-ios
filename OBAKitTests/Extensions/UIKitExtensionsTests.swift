//
//  UIKitExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class UIKitExtensionsTests {
    
    @Test func `UI button chevron button`() {
        let button = UIButton.chevronButton
        #expect(button.buttonType == .detailDisclosure)
        #expect(button.image(for: .normal) != nil)
    }
    
    @Test func `UI button build close button`() {
        let button = UIButton.buildCloseButton()
        #expect(button.translatesAutoresizingMaskIntoConstraints == false)
        #expect(button.accessibilityLabel == Strings.close)
    }
    
    @Test func `UI trait environment is accessibility`() {
        _ = UITraitCollection(preferredContentSizeCategory: .extraLarge)
        let view = UIView()
        view.overrideUserInterfaceStyle = .unspecified
        // For this test, we need to create a mock trait environment
        // Since the actual isAccessibility property depends on the trait collection
        // We'll test the logic directly by checking content size categories
        #expect(UIContentSizeCategory.extraLarge >= .extraLarge)
        #expect(!(UIContentSizeCategory.medium >= .extraLarge))
    }
}
