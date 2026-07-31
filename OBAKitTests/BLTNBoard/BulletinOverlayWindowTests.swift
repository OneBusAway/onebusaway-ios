//
//  BulletinOverlayWindowTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import BLTNBoard
@testable import OBAKit

/// Regression tests for the `BulletinOverlayWindow` handler-management fix from
/// issue #1170. The public `install(in:rootItem:)` path requires a live
/// `UIWindowScene`, which is fragile to synthesize in a test host, so these
/// tests drive the internal `swapDismissalHandler(on:)` / `restoreDismissalHandler()`
/// helpers directly — the same helpers `install`/`teardown` use.
///
/// **What these assert, and why it isn't a call count.** The pre-fix code
/// wrapped whatever handler was on the item and never put the original back, so
/// a reused item accumulated a chain of wrappers. A chain of N wrappers still
/// calls the caller's handler exactly once per dismissal — each wrapper invokes
/// its inner handler once — so "the original fired once per presentation" is
/// true of the buggy implementation too, and counting can't tell the two apart.
/// What differs is what the item holds *after* the bulletin is gone: chaining
/// leaves the overlay's wrapper installed (one deeper per presentation), the fix
/// leaves exactly what the caller set. That's what's asserted below, using an
/// item whose handler starts out `nil` so "restored to the caller's value" is
/// directly observable — no closure-identity comparison required.
@MainActor
@Suite(.serialized)
final class BulletinOverlayWindowTests {

    private let overlay = BulletinOverlayWindow.shared

    /// The overlay is a singleton shared with the rest of the test bundle. Any
    /// test that swaps without firing the wrapper would otherwise strand the
    /// swapped state on it.
    isolated deinit {
        overlay.restoreDismissalHandler()
    }

    /// Item 2 from issue #1170: on a reused page item (like
    /// `ReachabilityBulletin.connectivityPage`, re-shown on every connectivity
    /// flap), each presentation must leave the item exactly as it found it.
    ///
    /// Pre-fix, the post-dismissal assertion fails on the very first pass — the
    /// item is left holding wrapper 1 — and every later pass buries it one level
    /// deeper.
    @Test func `Repeated presentations leave no wrapper on a reused item`() {
        let page = BLTNPageItem(title: "Test")
        #expect(page.dismissalHandler == nil)

        for cycle in 1...5 {
            overlay.swapDismissalHandler(on: page)
            #expect(page.dismissalHandler != nil, "cycle \(cycle): the overlay's wrapper should be installed while the bulletin is up")

            // BLTN dispatching dismissal: the wrapper runs the caller's handler,
            // then tears the window down, which restores.
            page.dismissalHandler?(page)
            #expect(page.dismissalHandler == nil, "cycle \(cycle): dismissal should restore the item to the caller's handler, not leave a wrapper behind")
        }
    }

    /// Teardown must put the caller's handler back on the item, so the next
    /// presentation cycle starts from a pristine state.
    @Test func `Teardown restores the caller's handler`() {
        let page = BLTNPageItem(title: "Test")

        overlay.swapDismissalHandler(on: page)
        #expect(page.dismissalHandler != nil)

        page.dismissalHandler?(page)

        // Pre-fix, this is still the overlay's wrapper.
        #expect(page.dismissalHandler == nil)
    }

    /// A stale wrapper left on a dismissed item would reach back into the
    /// overlay and tear down whatever bulletin is up *now* — under the current
    /// implementation that also restores the live item's handler out from under
    /// it. This pins that a dismissed item is inert with respect to a later
    /// presentation of a different item.
    @Test func `A dismissed item cannot tear down a later presentation`() {
        let dismissed = BLTNPageItem(title: "Dismissed")
        overlay.swapDismissalHandler(on: dismissed)
        dismissed.dismissalHandler?(dismissed)

        let presented = BLTNPageItem(title: "Presented")
        overlay.swapDismissalHandler(on: presented)

        // The already-dismissed item is dismissed again (BLTN fires the handler
        // on `currentItem`; a caller can also invoke it directly).
        dismissed.dismissalHandler?(dismissed)

        // The live presentation is untouched: its wrapper is still installed.
        #expect(presented.dismissalHandler != nil)

        // Clean up: dismiss the live one for real.
        presented.dismissalHandler?(presented)
        #expect(presented.dismissalHandler == nil)
    }

    /// Forwarding: the wrapper has to run the caller's handler, once, with the
    /// item, on every presentation. This holds for the pre-fix implementation
    /// too — it's here to pin forwarding, not to distinguish the fix.
    @Test func `The caller's handler runs once per presentation, with the item`() {
        let page = BLTNPageItem(title: "Test")

        var callCount = 0
        var receivedItems: [ObjectIdentifier] = []
        page.dismissalHandler = { item in
            callCount += 1
            receivedItems.append(ObjectIdentifier(item))
        }

        for _ in 0..<5 {
            overlay.swapDismissalHandler(on: page)
            page.dismissalHandler?(page)
        }

        #expect(callCount == 5)
        #expect(receivedItems.allSatisfy { $0 == ObjectIdentifier(page) })

        // Restored to the caller's handler, so a direct call reaches it.
        page.dismissalHandler?(page)
        #expect(callCount == 6)
    }
}
