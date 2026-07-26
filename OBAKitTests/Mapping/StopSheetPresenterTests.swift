//
//  StopSheetPresenterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import UIKit
import FloatingPanel
@testable import OBAKit

/// Lifecycle tests for the half-detent sheet that presents the redesigned Stop page over the
/// map. The interactive parts (drag-to-expand, swipe-to-dismiss) are FloatingPanel's and are
/// verified by hand; what's tested here is the bookkeeping this app owns — that only one sheet
/// is ever onscreen, and that each presentation's cleanup runs exactly once.
@MainActor
final class StopSheetPresenterTests: XCTestCase {

    private var window: UIWindow!
    private var parent: UIViewController!
    private var presenter: StopSheetPresenter!

    override func setUp() async throws {
        try await super.setUp()

        parent = UIViewController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.view.layoutIfNeeded()

        presenter = StopSheetPresenter()
    }

    override func tearDown() async throws {
        presenter.dismiss(animated: false)
        presenter = nil
        window.isHidden = true
        window = nil
        parent = nil

        try await super.tearDown()
    }

    private var panels: [FloatingPanelController] {
        parent.children.compactMap { $0 as? FloatingPanelController }
    }

    /// Lets an in-flight presentation or dismissal animation finish. Measuring a panel that is
    /// still being animated into place reports whatever position that frame happened to catch.
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Presentation

    func test_present_addsOnePanelOpenedAtTheHalfDetent() {
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertTrue(presenter.isPresenting)
        XCTAssertEqual(panels.count, 1)
        XCTAssertEqual(panels.first?.state, .half)
    }

    /// The stop page publishes its Filter / More / Schedules chrome through `navigationItem`
    /// and pushes Trip screens through `ViewRouter`, both of which need a navigation
    /// controller. Losing this wrapper would silently drop the chrome and trip the router's
    /// `navigationController != nil` assertion.
    func test_present_wrapsContentInANavigationController() {
        let content = UIViewController()
        presenter.present(content, from: parent) {}

        let navigation = panels.first?.contentViewController as? UINavigationController
        XCTAssertNotNil(navigation)
        XCTAssertIdentical(navigation?.viewControllers.first, content)
    }

    /// Swipe-to-dismiss is off: the sheet header carries an explicit close button, and with
    /// removal enabled a downward flick past `.tip` tears the sheet down instead of settling
    /// there, which costs the rider the peek-at-the-map detent.
    func test_present_disablesSwipeToDismiss() {
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertEqual(panels.first?.isRemovalInteractionEnabled, false)
    }

    /// The tracked scroll view keeps its own content insets. FloatingPanel's default
    /// (`.always`) assigns `contentInset` outright on every layout pass, which wipes the top
    /// inset the stop page's `safeAreaInset(edge: .top)` header installs and strands the mode
    /// toggle and first departure underneath it.
    func test_present_leavesTheTrackedScrollViewsContentInsetsAlone() {
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertEqual(panels.first?.contentInsetAdjustmentBehavior, .never)
    }

    // MARK: - Replacement

    /// The HIG is explicit that one sheet shows at a time, and the map has several things
    /// competing for this space.
    func test_presentingASecondStop_leavesExactlyOnePanel() {
        presenter.present(UIViewController(), from: parent) {}
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertEqual(panels.count, 1)
        XCTAssertTrue(presenter.isPresenting)
    }

    /// Replacement must run the *outgoing* presentation's cleanup — the map uses it to
    /// deselect that stop's annotation, and running the incoming one instead would deselect
    /// the pin the rider just tapped.
    func test_presentingASecondStop_runsOnlyTheOutgoingDismissHandler() {
        var firstDismissed = 0
        var secondDismissed = 0

        presenter.present(UIViewController(), from: parent) { firstDismissed += 1 }
        presenter.present(UIViewController(), from: parent) { secondDismissed += 1 }

        XCTAssertEqual(firstDismissed, 1)
        XCTAssertEqual(secondDismissed, 0)
    }

    // MARK: - Dismissal

    func test_dismiss_clearsStateAndRunsTheHandler() {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.dismiss(animated: false)

        XCTAssertFalse(presenter.isPresenting)
        XCTAssertEqual(dismissed, 1)
    }

    func test_dismiss_isIdempotent() {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.dismiss(animated: false)
        presenter.dismiss(animated: false)

        XCTAssertEqual(dismissed, 1)
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
    func test_dismiss_slidesTheSheetStraightDownAtTheSizeItHad() throws {
        let (_, hosted) = makeTabBarHostedParent()

        for detent in [FloatingPanelState.full, .half, .tip] {
            let presenter = StopSheetPresenter()
            presenter.present(UIViewController(), from: hosted) {}

            spin(0.5)

            let panel = try XCTUnwrap(panels(in: hosted).first)
            panel.move(to: detent, animated: false)
            hosted.view.layoutIfNeeded()

            let surface = panel.surfaceView
            let contentView = try XCTUnwrap(surface.contentView)
            let frameBefore = surface.frame
            let contentHeightBefore = contentView.bounds.height

            presenter.dismiss(animated: true)
            hosted.view.layoutIfNeeded()

            XCTAssertEqual(
                surface.frame.minY, panel.view.bounds.maxY, accuracy: 0.5,
                "Dismissing from \(detent) left the sheet's top edge short of the bottom of the screen."
            )
            XCTAssertEqual(
                surface.frame.minX, frameBefore.minX, accuracy: 0.5,
                "Dismissing from \(detent) moved the sheet sideways."
            )
            XCTAssertEqual(
                surface.frame.height, frameBefore.height, accuracy: 0.5,
                "Dismissing from \(detent) resized the sheet instead of sliding it away."
            )
            XCTAssertEqual(
                contentView.bounds.height, contentHeightBefore, accuracy: 0.5,
                "Dismissing from \(detent) re-laid the stop page out mid-slide."
            )

            // Let the slide finish, so the next detent measures its own sheet rather than one
            // still on its way out.
            spin(0.5)
            XCTAssertEqual(panels(in: hosted).count, 0, "The \(detent) sheet never detached itself.")
        }
    }

    /// The tab bar's return is what changes the safe area the `.half` anchor is measured
    /// against, so it has to wait for the sheet to be gone — but it does still have to happen.
    func test_dismiss_animated_restoresTheHostTabBarOnceTheSheetHasGone() {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}
        spin(0.5)

        presenter.dismiss(animated: true)
        XCTAssertTrue(tabBarController.isTabBarHidden, "The tab bar came back while the sheet was still onscreen.")

        spin(0.8)
        XCTAssertFalse(tabBarController.isTabBarHidden, "The tab bar never came back after the sheet left.")
    }

    func test_dismiss_withNothingPresented_isANoOp() {
        presenter.dismiss(animated: false)
        XCTAssertFalse(presenter.isPresenting)
        XCTAssertEqual(panels.count, 0)
    }

    /// A swipe-away routes through `floatingPanelDidRemove` rather than `dismiss`, so it needs
    /// its own path to the same cleanup.
    func test_swipeAwayRemoval_runsTheHandlerAndClearsState() throws {
        var dismissed = 0
        presenter.present(UIViewController(), from: parent) { dismissed += 1 }

        presenter.floatingPanelDidRemove(try XCTUnwrap(panels.first))

        XCTAssertFalse(presenter.isPresenting)
        XCTAssertEqual(dismissed, 1)
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
    func test_present_hidesTheHostTabBar() {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        XCTAssertFalse(tabBarController.isTabBarHidden)

        presenter.present(UIViewController(), from: hosted) {}

        XCTAssertTrue(tabBarController.isTabBarHidden)
    }

    func test_dismiss_restoresTheHostTabBar() {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}

        presenter.dismiss(animated: false)

        XCTAssertFalse(tabBarController.isTabBarHidden)
    }

    /// Swiping the sheet away skips `dismiss`, so the tab bar has to come back on this path too
    /// or the rider is left with no way to change tabs.
    func test_swipeAwayRemoval_restoresTheHostTabBar() throws {
        let (tabBarController, hosted) = makeTabBarHostedParent()
        presenter.present(UIViewController(), from: hosted) {}

        presenter.floatingPanelDidRemove(try XCTUnwrap(panels(in: hosted).first))

        XCTAssertFalse(tabBarController.isTabBarHidden)
    }

    /// Tapping a second stop tears the first sheet down, but the bar must stay hidden the whole
    /// way through — restoring it mid-swap flashes it back behind the incoming sheet.
    func test_presentingASecondStop_keepsTheHostTabBarHidden() {
        let (tabBarController, hosted) = makeTabBarHostedParent()

        presenter.present(UIViewController(), from: hosted) {}
        presenter.present(UIViewController(), from: hosted) {}

        XCTAssertTrue(tabBarController.isTabBarHidden)
    }

    /// The map-panel experience presents the stop page outside a tab bar controller, so a nil
    /// host has to be a no-op rather than a crash.
    func test_present_withoutAHostTabBar_stillPresents() {
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertTrue(presenter.isPresenting)
        XCTAssertEqual(panels.count, 1)
    }

    private func panels(in parent: UIViewController) -> [FloatingPanelController] {
        parent.children.compactMap { $0 as? FloatingPanelController }
    }
}
