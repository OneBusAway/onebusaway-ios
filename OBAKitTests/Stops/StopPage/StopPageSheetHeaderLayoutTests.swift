//
//  StopPageSheetHeaderLayoutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import SwiftUI
import UIKit
import FloatingPanel
@testable import OBAKit
@testable import OBAKitCore

/// Geometry tests for the sheet header at the `.tip` detent.
///
/// The header is a `safeAreaInset(edge: .top)`, and SwiftUI does not crop one of those from the
/// bottom when it runs out of room — it keeps the view's ideal height, pins its lower edge to the
/// clamped inset boundary, and lets the remainder overflow *upward*, off the top of the sheet. So
/// the first things to leave the screen are the stop name and the close button, which is the one
/// outcome the peek detent cannot have: the rider is left with a nameless strip and no way out of
/// it. `StopPageSheetHeaderView(isCollapsed:)` exists to keep the header inside that budget, and
/// these tests measure whether it actually does.
@MainActor
final class StopPageSheetHeaderLayoutTests: XCTestCase {

    /// The home-indicator inset. It is load-bearing here: it comes out of the same height the top
    /// inset region is clamped against, so a simulator window without one hides the bug.
    private static let bottomSafeArea: CGFloat = 34.0
    private static let screenSize = CGSize(width: 402, height: 874)

    private var window: UIWindow!
    private var parent: UIViewController!
    private var presenter: StopSheetPresenter!

    override func setUp() async throws {
        try await super.setUp()

        parent = UIViewController()
        window = UIWindow(frame: CGRect(origin: .zero, size: Self.screenSize))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: Self.bottomSafeArea, right: 0)
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

    /// Stands in for `StopPageView`'s sheet presentation: the same `List` + top-inset header
    /// arrangement, with a probe reporting where the header actually lands.
    private struct Harness: View {
        let stop: Stop
        let isCollapsed: Bool
        let onHeaderFrame: (CGRect) -> Void

        var body: some View {
            List {
                ForEach(0..<30, id: \.self) { Text(verbatim: "row \($0)") }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                StopPageSheetHeaderView(
                    stop: stop,
                    walkTime: nil,
                    onWalkingDirections: {},
                    onClose: {},
                    isCollapsed: isCollapsed
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { onHeaderFrame(geo.frame(in: .global)) }
                            .onChange(of: geo.frame(in: .global)) { _, new in onHeaderFrame(new) }
                    }
                )
            }
        }
    }

    private struct TipLayout {
        /// Where the header ended up, in screen coordinates.
        let header: CGRect
        /// The top of the area the sheet gives its content — below the surface's grabber strip.
        let contentTop: CGFloat
    }

    /// Presents the harness, drops it to `.tip`, and reports where the header settled.
    private func layoutAtTip(isCollapsed: Bool) throws -> TipLayout {
        let stop = try XCTUnwrap(Fixtures.loadSomeStops().first)
        var headerFrame: CGRect = .null

        let content = UIHostingController(rootView: Harness(
            stop: stop,
            isCollapsed: isCollapsed,
            onHeaderFrame: { headerFrame = $0 }
        ))
        presenter.present(content, from: parent) {}

        let panel = try XCTUnwrap(parent.children.compactMap { $0 as? FloatingPanelController }.first)
        // The real sheet's root is a `StopPageViewController`, whose navigation bar the presenter
        // hides. A bare hosting controller keeps its bar, and the bar's own height would floor the
        // content view well above the detent — masking what this test is measuring.
        (panel.contentViewController as? UINavigationController)?.setNavigationBarHidden(true, animated: false)

        // Let the presentation animation land before moving; interrupting it mid-flight leaves
        // the surface wherever the animator had got to.
        spin(0.6)
        panel.move(to: .tip, animated: false)
        parent.view.layoutIfNeeded()
        spin(0.4)

        let contentFrame = try XCTUnwrap(panel.surfaceView.contentView).convert(
            try XCTUnwrap(panel.surfaceView.contentView).bounds,
            to: nil
        )

        return TipLayout(header: headerFrame, contentTop: contentFrame.minY)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// The peek detent has to show the stop name and the close button, or it is a strip of route
    /// badges the rider can't identify or dismiss.
    func test_collapsedHeader_fitsEntirelyWithinTheTipDetent() throws {
        let layout = try layoutAtTip(isCollapsed: true)

        XCTAssertGreaterThanOrEqual(
            layout.header.minY, layout.contentTop - 0.5,
            "The collapsed header overflowed the top of the sheet, taking the stop name and close button with it."
        )
        XCTAssertLessThanOrEqual(
            layout.header.maxY, Self.screenSize.height - Self.bottomSafeArea + 0.5,
            "The collapsed header ran past the safe area, so its lower half sits under the home indicator."
        )
    }

    /// The counterpart: the full header genuinely does not fit, which is why the collapsed variant
    /// exists at all. If SwiftUI ever starts cropping a top inset from the bottom instead — or the
    /// header slims down enough to fit — this test says so, and `isCollapsed` can be revisited.
    func test_fullHeader_doesNotFitTheTipDetent() throws {
        let layout = try layoutAtTip(isCollapsed: false)

        XCTAssertLessThan(
            layout.header.minY, layout.contentTop,
            "The full header now fits the tip detent; the collapsed variant may no longer be needed."
        )
    }

    /// The detent is sized from the collapsed header, so a rider running a large text size gets a
    /// taller peek rather than a clipped one.
    func test_tipDetentGrowsWithTheContentSizeCategory() {
        let standard = StopSheetHeaderMetrics.collapsedHeight(
            for: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let accessibility = StopSheetHeaderMetrics.collapsedHeight(
            for: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        )

        XCTAssertGreaterThan(accessibility, standard)
    }
}
