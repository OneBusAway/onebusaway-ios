//
//  StopSheetPresenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
import FloatingPanel
@testable import OBAKit

/// Lifecycle tests for the half-detent sheet that presents the redesigned Stop page over the
/// map. The interactive parts (drag-to-expand, swipe-to-dismiss) are FloatingPanel's and are
/// verified by hand; what's tested here is the bookkeeping this app owns — that only one sheet
/// is ever onscreen, and that each presentation's cleanup runs exactly once.
@MainActor
@Suite(.serialized)
final class StopSheetPresenterTests {

    private var window: UIWindow!
    private var parent: UIViewController!
    private var presenter: StopSheetPresenter!

    init() {
        parent = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.view.layoutIfNeeded()

        presenter = StopSheetPresenter()
    }

    // `isolated deinit` because the cleanup below touches main-actor UI state.
    // The `= nil` assignments the old `tearDown` performed are dropped: they
    // only mattered because XCTest holds test-case instances for the whole run,
    // and assigning nil inside `deinit` releases nothing extra regardless.
    isolated deinit {
        presenter.dismiss(animated: false)
        window.isHidden = true
    }

    private var panels: [FloatingPanelController] {
        parent.children.compactMap { $0 as? FloatingPanelController }
    }

    // MARK: - Presentation

    @Test func `Present adds one panel opened at the half detent`() {
        presenter.present(UIViewController(), from: parent) {}

        #expect(presenter.isPresenting)
        #expect(panels.count == 1)
        #expect(panels.first?.state == .half)
    }

    /// The stop page publishes its Filter / More / Schedules chrome through `navigationItem`
    /// and pushes Trip screens through `ViewRouter`, both of which need a navigation
    /// controller. Losing this wrapper would silently drop the chrome and trip the router's
    /// `navigationController != nil` assertion.
    @Test func `Present wraps content in a navigation controller`() {
        let content = UIViewController()
        presenter.present(content, from: parent) {}

        let navigation = panels.first?.contentViewController as? UINavigationController
        #expect(navigation != nil)
        #expect(navigation?.viewControllers.first === content)
    }

    /// Swipe-to-dismiss is off: the sheet header carries an explicit close button, and with
    /// removal enabled a downward flick past `.tip` tears the sheet down instead of settling
    /// there, which costs the rider the peek-at-the-map detent.
    @Test func `Present disables swipe to dismiss`() {
        presenter.present(UIViewController(), from: parent) {}

        #expect(panels.first?.isRemovalInteractionEnabled == false)
    }

    /// The tracked scroll view keeps its own content insets. FloatingPanel's default
    /// (`.always`) assigns `contentInset` outright on every layout pass, which wipes the top
    /// inset the stop page's `safeAreaInset(edge: .top)` header installs and strands the mode
    /// toggle and first departure underneath it.
    @Test func `Present leaves the tracked scroll views content insets alone`() {
        presenter.present(UIViewController(), from: parent) {}

        #expect(panels.first?.contentInsetAdjustmentBehavior == .never)
    }

    // MARK: - Replacement

    /// The HIG is explicit that one sheet shows at a time, and the map has several things
    /// competing for this space.
    @Test func `Presenting a second stop leaves exactly one panel`() {
        presenter.present(UIViewController(), from: parent) {}
        presenter.present(UIViewController(), from: parent) {}

        #expect(panels.count == 1)
        #expect(presenter.isPresenting)
    }

    /// Replacement must run the *outgoing* presentation's cleanup — the map uses it to
    /// deselect that stop's annotation, and running the incoming one instead would deselect
    /// the pin the rider just tapped.
    @Test func `Presenting a second stop runs only the outgoing dismiss handler`() {
        var firstDismissed = 0
        var secondDismissed = 0

        presenter.present(UIViewController(), from: parent) { firstDismissed += 1 }
        presenter.present(UIViewController(), from: parent) { secondDismissed += 1 }

        #expect(firstDismissed == 1)
        #expect(secondDismissed == 0)
    }

    // MARK: - Pushed content

    /// Stands in for the stop page: the only thing the presenter asks of it is where the
    /// sheet is sitting.
    /// A page that supplies its own title and back affordance, like the trip page.
    private final class SelfChromedStub: UIViewController, StopSheetSelfChromedContent {
        let providesOwnSheetChrome = true
        var sheetSurfaceColor: UIColor?

        init(surfaceColor: UIColor? = nil) {
            self.sheetSurfaceColor = surfaceColor
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("unused") }
    }

    private final class CollapsibleStub: UIViewController, StopSheetCollapsibleContent {
        private(set) var atTipHistory: [Bool] = []
        func setAtTip(_ isAtTip: Bool) { atTipHistory.append(isAtTip) }
    }

    private func presentedNavigation() throws -> UINavigationController {
        try #require(panels.first?.contentViewController as? UINavigationController)
    }

    /// Pushes onto the sheet's stack, then hands the presenter the delegate callbacks that go
    /// with the push.
    ///
    /// The callbacks are invoked rather than awaited: a navigation controller that has never
    /// really been on screen doesn't run the transition machinery UIKit drives them from, so
    /// headlessly `pushViewController` alone produces neither. Verified, not assumed — the
    /// callbacks stay silent through a spun runloop. `present` already works around the same
    /// gap for the root controller, seeding the bar state itself rather than waiting for
    /// `willShow`. The push itself is real so the root-identity check has a real stack.
    private func push(_ viewController: UIViewController, onto navigation: UINavigationController) {
        navigation.pushViewController(viewController, animated: false)
        presenter.navigationController(navigation, willShow: viewController, animated: false)
        presenter.navigationController(navigation, didShow: viewController, animated: false)
    }

    /// Puts the sheet at a starting detent and confirms it got there.
    ///
    /// FloatingPanel swallows a `move` issued immediately after a push — it is still
    /// settling the layout the push invalidated. Real riders drag the sheet a frame or two
    /// later; a test driving the delegate by hand arrives inside that window. Laying out and
    /// re-issuing keeps a test that means to start at `.tip` from quietly measuring `.half`.
    private func settle(_ panel: FloatingPanelController, at state: FloatingPanelState) {
        panel.move(to: state, animated: false)
        parent.view.layoutIfNeeded()
        if panel.state != state {
            panel.move(to: state, animated: false)
        }
        #expect(panel.state == state, "the sheet never reached \(state)")
    }

    private func popBack(in navigation: UINavigationController) throws {
        navigation.popViewController(animated: false)
        #expect(navigation.viewControllers.count == 1, "the pop didn't take")
        let top = try #require(navigation.topViewController)
        presenter.navigationController(navigation, willShow: top, animated: false)
        presenter.navigationController(navigation, didShow: top, animated: false)
    }

    /// A screen pushed while the sheet peeks at `.tip` lands entirely below the fold — the
    /// rider taps "Follow this trip", a trip screen is pushed, and nothing visibly happens.
    @Test func `Pushing over the stop page raises a tip sheet to half`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let panel = try #require(panels.first)
        settle(panel, at: .tip)

        push(UIViewController(), onto: try presentedNavigation())

        #expect(panel.state == .half)
    }

    /// Only `.tip` is broken. Anywhere else the pushed screen is already on screen, and moving
    /// the sheet under the rider would be its own surprise — a rider who expanded to `.full`
    /// must not be dropped to `.half` by a push.
    @Test func `Pushing leaves a sheet the rider already expanded alone`() throws {
        for detent in [FloatingPanelState.half, .full] {
            // Replaces the previous iteration's sheet, so `panels` stays at one.
            presenter.present(CollapsibleStub(), from: parent) {}
            let panel = try #require(panels.first)
            settle(panel, at: detent)

            push(UIViewController(), onto: try presentedNavigation())

            #expect(panel.state == detent)
        }
    }

    /// Coming back is not a push: a rider who dragged the sheet down while reading a pushed
    /// screen means to keep peeking at the map.
    @Test func `Popping back to the stop page leaves a tip sheet where it is`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let panel = try #require(panels.first)
        let navigation = try presentedNavigation()
        push(UIViewController(), onto: navigation)
        settle(panel, at: .tip)

        try popBack(in: navigation)

        #expect(panel.state == .tip)
    }

    /// `floatingPanelDidChangeState` only speaks to the top of the stack, so every detent
    /// change made while something is pushed over the stop page passes it by — including the
    /// raise above. Without a re-sync on the way back, the page returns to a `.half` sheet
    /// still drawing the collapsed header built for `.tip`.
    @Test func `Returning to the stop page re-syncs its collapsed state`() throws {
        let page = CollapsibleStub()
        presenter.present(page, from: parent) {}
        let panel = try #require(panels.first)
        settle(panel, at: .tip)
        #expect(page.atTipHistory.last == true)

        let navigation = try presentedNavigation()
        push(UIViewController(), onto: navigation)
        // The push raised the sheet, but the page was not on top to hear about it.
        #expect(panel.state == .half)
        #expect(page.atTipHistory.last == true)

        try popBack(in: navigation)

        #expect(page.atTipHistory.last == false)
    }

    // MARK: - Dismissal

    @Test func `Dismiss clears state and runs the handler`() {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.dismiss(animated: false)

        #expect(!presenter.isPresenting)
        #expect(dismissed == 1)
    }

    @Test func `Dismiss is idempotent`() {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.dismiss(animated: false)
        presenter.dismiss(animated: false)

        #expect(dismissed == 1)
    }

    /// A dismissal should look like one thing leaving: the sheet travels straight down, at the
    /// size the rider was just looking at, until it clears the bottom edge.
    ///
    /// Two mechanics make that harder than it sounds, and both showed up worst at `.half`.
    /// FloatingPanel's `hide(animated:)` animates the surface's *layout*, and under
    /// `.fitToBounds` the hidden anchor drives the surface's top edge down to the bottom of the
    /// screen while the fit-to-bounds constraint goes on holding its bottom edge there — the
    /// sheet collapses in place rather than travelling, re-laying the stop page out on every
    /// frame. And restoring the tab bar grows the map's bottom safe area, which re-solves the
    /// `.half` anchor's fraction *of* that safe area and hauls the sheet up the screen mid-exit.
    ///
    /// Measured against the panel's own view: the surface ends flush with the bottom edge, and
    /// neither it nor the page inside it changed size on the way there.
    @Test func `Dismiss slides the sheet straight down at the size it had`() async throws {
        let (_, hosted) = makeTabBarHostedParent()

        for detent in [FloatingPanelState.full, .half, .tip] {
            let presenter = StopSheetPresenter()
            presenter.present(UIViewController(), from: hosted) {}

            await spin(0.5)

            let panel = try #require(panels(in: hosted).first)
            panel.move(to: detent, animated: false)
            hosted.view.layoutIfNeeded()

            let surface = panel.surfaceView
            let contentView = try #require(surface.contentView)
            let frameBefore = surface.frame
            let contentHeightBefore = contentView.bounds.height

            presenter.dismiss(animated: true)
            hosted.view.layoutIfNeeded()

            expectClose(surface.frame.minY, panel.view.bounds.maxY, within: 0.5, "Dismissing from \(detent) left the sheet's top edge short of the bottom of the screen.")
            expectClose(surface.frame.minX, frameBefore.minX, within: 0.5, "Dismissing from \(detent) moved the sheet sideways.")
            expectClose(surface.frame.height, frameBefore.height, within: 0.5, "Dismissing from \(detent) resized the sheet instead of sliding it away.")
            expectClose(contentView.bounds.height, contentHeightBefore, within: 0.5, "Dismissing from \(detent) re-laid the stop page out mid-slide.")

            // Let the slide finish, so the next detent measures its own sheet rather than one
            // still on its way out.
            await spin(0.5)
            #expect(panels(in: hosted).count == 0, "The \(detent) sheet never detached itself.")
        }
    }

    /// The tab bar's return is what changes the safe area the `.half` anchor is measured
    /// against, so it has to wait for the sheet to be gone — but it does still have to happen.
    @Test func `Dismiss animated restores the host tab bar once the sheet has gone`() async {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}
        await spin(0.5)

        presenter.dismiss(animated: true)
        #expect(tabBarController.isTabBarHidden, "The tab bar came back while the sheet was still onscreen.")

        await spin(0.8)
        #expect(!tabBarController.isTabBarHidden, "The tab bar never came back after the sheet left.")
    }

    @Test func `Dismiss with nothing presented is a no op`() {
        presenter.dismiss(animated: false)
        #expect(!presenter.isPresenting)
        #expect(panels.count == 0)
    }

    /// A swipe-away routes through `floatingPanelDidRemove` rather than `dismiss`, so it needs
    /// its own path to the same cleanup.
    @Test func `Swipe away removal runs the handler and clears state`() throws {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.floatingPanelDidRemove(try #require(panels.first))

        #expect(!presenter.isPresenting)
        #expect(dismissed == 1)
    }

    // MARK: - Tab Bar

    /// Mirrors the real hierarchy: the map sits in a navigation controller inside the tab bar
    /// controller, which is why the tab bar draws over anything the map parents a panel to.
    private func makeTabBarHostedParent() -> (tabBarController: UITabBarController, hosted: UIViewController) {
        let hosted = UIViewController()
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [UINavigationController(rootViewController: hosted)]
        window.rootViewController = tabBarController
        tabBarController.view.layoutIfNeeded()

        return (tabBarController, hosted)
    }

    /// The tab bar can't be beaten on z-order from inside the map, so the sheet hides it to
    /// claim the bottom edge of the screen for its own chrome.
    @Test func `Present hides the host tab bar`() {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        #expect(!tabBarController.isTabBarHidden)

        presenter.present(UIViewController(), from: hosted) {}

        #expect(tabBarController.isTabBarHidden)
    }

    @Test func `Dismiss restores the host tab bar`() {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}

        presenter.dismiss(animated: false)

        #expect(!tabBarController.isTabBarHidden)
    }

    /// Swiping the sheet away skips `dismiss`, so the tab bar has to come back on this path too
    /// or the rider is left with no way to change tabs.
    @Test func `Swipe away removal restores the host tab bar`() throws {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}

        presenter.floatingPanelDidRemove(try #require(panels(in: hosted).first))

        #expect(!tabBarController.isTabBarHidden)
    }

    /// Tapping a second stop tears the first sheet down, but the bar must stay hidden the whole
    /// way through — restoring it mid-swap flashes it back behind the incoming sheet.
    @Test func `Presenting a second stop keeps the host tab bar hidden`() {
        let (tabBarController, hosted) = makeTabBarHostedParent()

        presenter.present(UIViewController(), from: hosted) {}
        presenter.present(UIViewController(), from: hosted) {}

        #expect(tabBarController.isTabBarHidden)
    }

    /// The map-panel experience presents the stop page outside a tab bar controller, so a nil
    /// host has to be a no-op rather than a crash.
    @Test func `Present without a host tab bar still presents`() {
        presenter.present(UIViewController(), from: parent) {}

        #expect(presenter.isPresenting)
        #expect(panels.count == 1)
    }

    private func panels(in parent: UIViewController) -> [FloatingPanelController] {
        parent.children.compactMap { $0 as? FloatingPanelController }
    }

    // MARK: - Navigation bar

    /// A pushed page that draws its own back affordance must not also get a bar:
    /// the result is two back buttons and a strip of empty chrome above the
    /// page's own header.
    @Test func `A page that draws its own header is pushed without a navigation bar`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()

        push(SelfChromedStub(), onto: navigation)

        #expect(navigation.isNavigationBarHidden)
    }

    /// The rule is asked of the page, not assumed for everything pushed — an
    /// ordinary screen still needs its bar to be navigable.
    @Test func `A page with no header of its own keeps the navigation bar`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()

        push(UIViewController(), onto: navigation)

        #expect(!navigation.isNavigationBarHidden)
    }

    /// Popping back to the sheet's root restores the root's own answer, rather
    /// than leaving the pushed page's behind.
    @Test func `Popping back from a self-chromed page restores the root's bar state`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()
        push(SelfChromedStub(), onto: navigation)

        try popBack(in: navigation)

        // `CollapsibleStub` is not self-chromed, so the root wants its bar back.
        #expect(!navigation.isNavigationBarHidden)
    }

    /// The navigation controller is inset by the grabber clearance, so the strip behind the
    /// grabber is painted by the surface. A page whose background isn't `.systemBackground`
    /// gets a white bar across the top of the sheet unless the surface follows it.
    @Test func `Pushing a page with its own background repaints the grabber strip`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()
        let panel = try #require(panels.first)
        #expect(panel.surfaceView.appearance.backgroundColor == .systemBackground)

        push(SelfChromedStub(surfaceColor: .systemGroupedBackground), onto: navigation)

        #expect(panel.surfaceView.appearance.backgroundColor == .systemGroupedBackground)
    }

    @Test func `Popping back restores the root's grabber strip`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()
        let panel = try #require(panels.first)
        push(SelfChromedStub(surfaceColor: .systemGroupedBackground), onto: navigation)

        try popBack(in: navigation)

        #expect(panel.surfaceView.appearance.backgroundColor == .systemBackground)
    }

    /// A self-chromed page that doesn't ask for a color leaves the strip alone.
    @Test func `A page with no background preference leaves the grabber strip alone`() throws {
        presenter.present(CollapsibleStub(), from: parent) {}
        let navigation = try presentedNavigation()
        let panel = try #require(panels.first)

        push(SelfChromedStub(), onto: navigation)

        #expect(panel.surfaceView.appearance.backgroundColor == .systemBackground)
    }
}
