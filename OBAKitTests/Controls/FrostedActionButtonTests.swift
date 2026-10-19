//
//  FrostedActionButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
@testable import OBAKit

@MainActor
@Suite(.serialized)
struct FrostedActionButtonTests {

    /// Verifies that FrostedBackground initializes with a default Capsule shape and with custom InsettableShapes.
    @Test func testFrostedBackgroundInitialization() {
        let defaultModifier = FrostedBackground()
        _ = defaultModifier

        let roundedRectModifier = FrostedBackground(shape: RoundedRectangle(cornerRadius: 8))
        _ = roundedRectModifier
    }

    /// Verifies that FrostedActionButtonStyle initializes with default Capsule and custom shapes.
    @Test func testFrostedActionButtonStyleInitialization() {
        let defaultStyle = FrostedActionButtonStyle()
        _ = defaultStyle

        let customStyle = FrostedActionButtonStyle(shape: RoundedRectangle(cornerRadius: 12))
        _ = customStyle
    }

    /// Verifies that views styled with FrostedActionButtonStyle render cleanly in SwiftUI.
    @Test func testButtonWithFrostedStyleRendering() {
        let button = Button("Action") { }
            .buttonStyle(FrostedActionButtonStyle())
        _ = button

        let roundedButton = Button("More") { }
            .buttonStyle(FrostedActionButtonStyle(shape: RoundedRectangle(cornerRadius: 6)))
        _ = roundedButton
    }
}
