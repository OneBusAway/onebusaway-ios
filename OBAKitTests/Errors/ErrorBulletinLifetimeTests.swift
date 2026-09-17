//
//  ErrorBulletinLifetimeTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// #1429 / #1421: the presented error card has to keep working even when the
/// reference that created it goes away.
///
/// `ErrorBulletin.present(_:)` documents why it otherwise doesn't. In the app,
/// the reference being dropped is `Application.errorBulletin`: a single slot,
/// reassigned by the next error to arrive.
@Suite(.serialized)
@MainActor
final class ErrorBulletinLifetimeTests: OBATestCase {

    private var window: UIWindow!
    private var hostVC: UIViewController!
    private var application: Application!
    /// Owned by the suite so `deinit` can cancel it — `buildApplication` kicks
    /// off regions/agencies loads that would otherwise outlive the test.
    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        application = buildApplication(queue: queue, dataLoader: MockDataLoader(testName: name))

        // A real `UIWindowScene` is required: UIKit won't run a presentation
        // into a scene-less window, and `isShowing` reads the result of that
        // presentation.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(
            scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
            "No UIWindowScene in the test host."
        )

        hostVC = UIViewController()
        window = UIWindow(windowScene: scene)
        // Above the test host's own UI, matching where the app puts bulletins.
        window.windowLevel = .alert
        window.rootViewController = hostVC
        window.isHidden = false
        window.layoutIfNeeded()
    }

    /// A visible `UIWindow` is retained by its `UIWindowScene`, so leaving one
    /// behind would stack an `.alert`-level window over every later suite's UI
    /// — once per test in this suite. Hiding it releases it. Matches
    /// `StopSheetPresenterTests`.
    ///
    /// Optional-chained throughout: `init` can throw at its `#require` after
    /// `super.init()` has run, and Swift still runs `deinit` on that
    /// partially-initialized instance — where `window` and `hostVC` are `nil`.
    isolated deinit {
        hostVC?.presentedViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        window?.isHidden = true
        queue?.cancelAllOperations()
    }

    private func makeBulletin() -> ErrorBulletin {
        ErrorBulletin(
            application: application,
            classifiedError: NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "404 Not found"])
        )
    }

    /// `Application.displayError`'s "is one already up?" guard (#1422) reads
    /// `isShowing`, i.e. `bulletinController.presentingViewController != nil`.
    /// That has to flip synchronously inside `show`, or the guard lets a second
    /// bulletin through on the very next main-actor turn — exactly the burst
    /// the Bookmarks screen produces, since `BookmarkDataLoader` runs one fetch,
    /// and one `displayError`, per bookmark.
    @Test func `isShowing flips synchronously when the card is presented`() async {
        let bulletin = makeBulletin()
        #expect(bulletin.isShowing == false)

        bulletin.show(above: hostVC, animated: false)
        #expect(bulletin.isShowing == true)

        await dismiss(bulletin)
    }

    /// The regression. Presenting hands the card to UIKit; dropping the last
    /// strong reference must not take the card's brain with it.
    @Test func `Presented card outlives the reference that created it`() async {
        weak var weakBulletin: ErrorBulletin?
        weak var weakButton: UIButton?

        do {
            let bulletin = makeBulletin()
            bulletin.show(above: hostVC, animated: false)
            await settleAfterPresenting()

            weakBulletin = bulletin
            weakButton = bulletin.dismissButton

            #expect(bulletin.isShowing == true)
            #expect(weakButton != nil, "Presentation should have built the Dismiss button.")
        }
        // Leaving the scope is the whole story: in the app this is
        // `Application.errorBulletin` being reassigned by the next error.

        #expect(weakBulletin != nil, "The presented bulletin deallocated while its card was still on screen — Dismiss is now dead (#1429).")
        #expect(weakButton?.allTargets.isEmpty == false, "Dismiss lost its target-action, so tapping it does nothing (#1429).")

        if let bulletin = weakBulletin {
            await dismiss(bulletin)
        }
    }

    /// The card is still on screen, so tapping Dismiss has to actually dismiss
    /// it — that button is the user's only way out.
    @Test func `Dismiss still works after the creating reference is dropped`() async {
        weak var weakBulletin: ErrorBulletin?

        do {
            let bulletin = makeBulletin()
            bulletin.show(above: hostVC, animated: false)
            await settleAfterPresenting()
            weakBulletin = bulletin
        }

        #expect(hostVC.presentedViewController != nil, "Precondition: the card is presented.")

        weakBulletin?.dismissButton?.sendActions(for: .touchUpInside)
        await poll(until: { self.hostVC.presentedViewController == nil }, "tapping Dismiss left the card on screen (#1429)")
    }

    /// Holding the bulletin alive for the presentation must not hold it alive
    /// forever — otherwise the wedge just becomes a leak.
    @Test func `Bulletin is released once its card is dismissed`() async {
        weak var weakBulletin: ErrorBulletin?

        do {
            let bulletin = makeBulletin()
            bulletin.show(above: hostVC, animated: false)
            await settleAfterPresenting()
            weakBulletin = bulletin
            await dismiss(bulletin)
        }

        await poll(until: { weakBulletin == nil }, "the bulletin outlived its presentation — the self-reference leaked")
    }

    /// #1429 end to end. Whatever lets a second card stack on the first — and
    /// `Application.displayError`'s guard is not the only producer of bulletins
    /// — the user has to be able to tap their way back out.
    @Test func `Both cards dismiss when two stack up`() async throws {
        // Stands in for `Application.errorBulletin`: one slot, holding only the
        // newest bulletin.
        var errorBulletin: ErrorBulletin?
        weak var weakFirst: ErrorBulletin?

        errorBulletin = makeBulletin()
        errorBulletin?.show(above: hostVC, animated: false)
        await settleAfterPresenting()
        weakFirst = errorBulletin

        // The second presents above the first, because `topViewController`
        // walks the `presentedViewController` chain. Requiring the first card
        // rather than falling back to `hostVC` keeps a failed first
        // presentation from quietly turning this into a one-card test.
        let top = try #require(hostVC.presentedViewController, "Precondition: the first card is presented.")
        let second = makeBulletin()
        second.show(above: top, animated: false)
        // Reassigning the slot is what drops the first bulletin's only owner.
        errorBulletin = second
        await settleAfterPresenting()

        #expect(second.isShowing == true, "Precondition: two cards are stacked.")

        await dismiss(second, expectingHostClear: false)
        #expect(hostVC.presentedViewController != nil, "The first card should still be up.")

        weakFirst?.dismissButton?.sendActions(for: .touchUpInside)
        await poll(until: { self.hostVC.presentedViewController == nil }, "the first card wouldn't dismiss — the app is wedged (#1429)")

        withExtendedLifetime(errorBulletin) {}
    }

    /// A bulletin that never made it on screen must not retain itself: no
    /// dismissal is coming to release it.
    @Test func `Bulletin that fails to present retains nothing`() async {
        weak var weakBulletin: ErrorBulletin?

        do {
            let bulletin = makeBulletin()
            // A detached controller can't present, so nothing goes on screen.
            bulletin.show(above: UIViewController(), animated: false)
            await settleAfterPresenting()
            weakBulletin = bulletin
            #expect(bulletin.isShowing == false)
        }

        #expect(weakBulletin == nil, "A bulletin that never presented retained itself and leaked.")
    }

    // MARK: - Helpers

    /// Taps Dismiss and waits for the card to come down.
    ///
    /// `expectingHostClear` is false when another card is stacked underneath
    /// this one, so the host keeps a `presentedViewController` either way.
    private func dismiss(_ bulletin: ErrorBulletin, expectingHostClear: Bool = true) async {
        await settleAfterPresenting()
        bulletin.dismissButton?.sendActions(for: .touchUpInside)

        if expectingHostClear {
            await poll(until: { self.hostVC.presentedViewController == nil }, "the card never came down")
        } else {
            await poll(until: { bulletin.isShowing == false }, "the card never came down")
        }
    }

    /// Lets BLTNBoard deliver the completion block of the interface refresh it
    /// kicks off while preparing.
    ///
    /// Dismissing before that block runs crashes the test host: `completeDismissal`
    /// nils out `bulletinController`, and the queued block force-unwraps it. The
    /// refresh has no observable end state to poll for — it animates with
    /// duration 0 and only posts a completion — which is what `spin` is for.
    private func settleAfterPresenting() async {
        await spin(0.15)
    }
}
