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

    func test_present_enablesSwipeToDismiss() {
        presenter.present(UIViewController(), from: parent) {}

        XCTAssertEqual(panels.first?.isRemovalInteractionEnabled, true)
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
}
