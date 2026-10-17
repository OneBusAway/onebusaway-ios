//
//  SheetNavigationControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import UIKit
@testable import OBAKit

/// The vertical tab bar column that causes the excess inset only exists on an iPhone Duo with
/// a tab bar controller at the window's root, which a hosted test can't set up; these cover
/// the arithmetic that removes it, and when a sheet opts out of vertical bars.
@Suite(.serialized)
struct SheetNavigationControllerTests {
    private func corrected(page: UIEdgeInsets, additional: UIEdgeInsets = .zero, container: UIEdgeInsets) -> UIEdgeInsets {
        SheetNavigationController.correctedAdditionalSafeArea(page: page, additional: additional, container: container)
    }

    @Test func removesTrailingInsetTheSheetDoesNotHave() {
        let result = corrected(
            page: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            container: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )
        #expect(result == UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -84))
    }

    @Test func isStableOnceApplied() {
        // After the correction lands, the page's inset matches the container's.
        let result = corrected(
            page: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            additional: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -84),
            container: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )
        #expect(result == UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -84))
    }

    @Test func keepsInsetTheSheetReallyHas() {
        let result = corrected(
            page: UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 44),
            container: UIEdgeInsets(top: 0, left: 44, bottom: 0, right: 44)
        )
        #expect(result == .zero)
    }

    @Test func leavesTopAndBottomAlone() {
        let result = corrected(
            page: UIEdgeInsets(top: 52, left: 0, bottom: 34, right: 0),
            additional: UIEdgeInsets(top: 8, left: 0, bottom: 4, right: 0),
            container: .zero
        )
        #expect(result == UIEdgeInsets(top: 8, left: 0, bottom: 4, right: 0))
    }

    @Test @MainActor func onlyAPresentedSheetOptsOutOfVerticalBars() {
        guard #available(iOS 27.1, *) else { return }
        // Pushed onto the window's own stack, the preference would reach the window and lay
        // the tab bar out horizontally.
        let unpresented = SheetHostingController(rootView: EmptyView())
        #expect(unpresented.preferredVerticalBarBehavior == .automatic)
        #expect(SheetNavigationController().preferredVerticalBarBehavior == .automatic)
    }
}
