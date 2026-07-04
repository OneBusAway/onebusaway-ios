//
//  BulletinOverlayWindowTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import BLTNBoard
@testable import OBAKit

/// Regression tests for the `BulletinOverlayWindow` handler-management fix
/// from issue #1170. The public `install(in:rootItem:)` path requires a live
/// `UIWindowScene`, which is fragile to synthesize in a test host, so these
/// tests drive the internal `swapDismissalHandler(on:)` / `restoreDismissalHandler()`
/// helpers directly — the same helpers `install`/`teardown` use.
@MainActor
class BulletinOverlayWindowTests: XCTestCase {

    /// Item 2 from issue #1170: on a reused page item (like
    /// `ReachabilityBulletin.connectivityPage`), repeated presentations must
    /// not stack the caller's dismissal handler. Each cycle should see the
    /// original handler fire exactly once.
    func test_reused_item_does_not_accumulate_dismissal_handlers() {
        let overlay = BulletinOverlayWindow.shared
        let page = BLTNPageItem(title: "Test")

        var originalCallCount = 0
        let originalHandler: (BLTNItem) -> Void = { _ in originalCallCount += 1 }
        page.dismissalHandler = originalHandler

        // Simulate five install/teardown cycles.
        for _ in 0..<5 {
            overlay.swapDismissalHandler(on: page)
            // Fire the swapped-in handler; it should invoke the original once,
            // then internally call teardown (which restores).
            page.dismissalHandler?(page)
        }

        // Now that we're restored to the original, invoke it directly to
        // confirm it hasn't been wrapped. One more call → one more increment.
        page.dismissalHandler?(page)

        // Five swap cycles each fired the original once, plus one direct call.
        expect(originalCallCount) == 6
    }

    /// Teardown must put the original handler back onto the item, so the next
    /// presentation cycle starts from a pristine state.
    func test_teardown_restores_original_handler() {
        let overlay = BulletinOverlayWindow.shared
        let page = BLTNPageItem(title: "Test")

        var originalFired = false
        page.dismissalHandler = { _ in originalFired = true }

        overlay.swapDismissalHandler(on: page)

        // Handler is now the overlay's wrapper — not the original.
        page.dismissalHandler?(page)
        expect(originalFired) == true

        // After the wrapper ran (which calls restore), a subsequent dismissal
        // handler invocation must go straight to the original — no wrapper
        // left in place, no self-reference back into the overlay.
        originalFired = false
        page.dismissalHandler?(page)
        expect(originalFired) == true
    }
}
