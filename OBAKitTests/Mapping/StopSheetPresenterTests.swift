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

    /// `hide(animated:)` installs the hidden state's constraints in a single layout pass and then
    /// animates only the layers. Under `.fitToBounds` the hidden anchor leaves the content view
    /// almost no height, so without intervention the stop page re-lays itself out for a ~100 pt
    /// box on the animation's first frame: for the third of a second the sheet takes to slide
    /// away, the rider watches it collapse into a clipped strip of header over the toolbar, with a
    /// tall band of empty surface beneath. Freezing the height turns that back into a slide.
    func test_dismiss_keepsTheContentAtItsCurrentSizeWhileTheSheetSlidesAway() throws {
        for detent in [FloatingPanelState.full, .half, .tip] {
            let presenter = StopSheetPresenter()
            presenter.present(UIViewController(), from: parent) {}

            let panel = try XCTUnwrap(panels.first)
            panel.move(to: detent, animated: false)
            parent.view.layoutIfNeeded()

            let contentView = try XCTUnwrap(panel.surfaceView.contentView)
            let heightBefore = contentView.bounds.height

            presenter.dismiss(animated: true)
            parent.view.layoutIfNeeded()

            XCTAssertEqual(
                contentView.bounds.height, heightBefore, accuracy: 0.5,
                "Dismissing from \(detent) re-laid the sheet's content out at the hidden anchor's height instead of sliding it away."
            )

            presenter.dismiss(animated: false)
        }
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
