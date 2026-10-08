//
//  MarqueeLabelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

/// Covers the vendored MarqueeLabel in `OBAKit/ThirdParty/MarqueeLabel`,
/// including regressions for the `OBA:` fixes made there.
@MainActor
@Suite(.serialized)
struct MarqueeLabelTests {

    private static let longText = String(repeating: "Downtown Seattle via Rainier Ave S ", count: 4)

    private func makeLabel(text: String = longText, width: CGFloat = 100) -> MarqueeLabel {
        let label = MarqueeLabel(frame: CGRect(x: 0, y: 0, width: width, height: 20))
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.text = text
        return label
    }

    // MARK: - labelShouldScroll

    @Test func `Text wider than the label scrolls`() throws {
        try #require(!UIAccessibility.isReduceMotionEnabled)
        #expect(makeLabel().labelShouldScroll())
    }

    @Test func `Text that fits does not scroll`() {
        #expect(!makeLabel(text: "1", width: 100).labelShouldScroll())
    }

    @Test func `Empty text does not scroll`() {
        #expect(!makeLabel(text: "").labelShouldScroll())
    }

    @Test func `Labelized label does not scroll`() {
        let label = makeLabel()
        label.labelize = true
        #expect(!label.labelShouldScroll())
    }

    /// Upstream measured the text with `UIFont(name:size:)` at 0 pt when
    /// `minimumScaleFactor` was 0 (UILabel's default, meaning "don't shrink"). That
    /// returns 0 pt Helvetica, which measures negative, so a label with
    /// `adjustsFontSizeToFitWidth` never scrolled. `StackedMarqueeTitleView`
    /// configures its labels exactly this way.
    @Test func `Auto-shrinking label with a zero scale factor scrolls`() throws {
        try #require(!UIAccessibility.isReduceMotionEnabled)
        let label = makeLabel()
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0
        #expect(label.labelShouldScroll())
    }

    @Test func `Auto-shrinking label that fits once shrunk does not scroll`() {
        let text = "Rainier Ave S"
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let fullWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let label = makeLabel(text: text, width: ceil(fullWidth * 0.75))
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        #expect(!label.labelShouldScroll())
    }

    @Test func `Auto-shrinking label that is too wide even when shrunk scrolls`() throws {
        try #require(!UIAccessibility.isReduceMotionEnabled)
        let label = makeLabel()
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        #expect(label.labelShouldScroll())
    }

    // MARK: - tapToScroll

    /// Upstream removed whichever recognizer was first.
    @Test func `Turning tapToScroll off removes only its own recognizer`() throws {
        let label = makeLabel()
        let other = UILongPressGestureRecognizer()
        label.addGestureRecognizer(other)

        label.tapToScroll = true
        #expect(label.gestureRecognizers?.count == 2)
        #expect(label.isUserInteractionEnabled)

        label.tapToScroll = false
        let remaining = try #require(label.gestureRecognizers)
        #expect(remaining.count == 1)
        #expect(remaining.first === other)
        #expect(!label.isUserInteractionEnabled)
    }

    @Test func `Turning tapToScroll off after its recognizer was removed`() {
        let label = makeLabel()
        label.tapToScroll = true
        label.gestureRecognizers?.forEach(label.removeGestureRecognizer)

        label.tapToScroll = false
        #expect(label.gestureRecognizers?.isEmpty ?? true)
    }

    // MARK: - Pausing

    /// The fade mask is absent when `fadeLength` is 0, and pausing reaches it
    /// through force unwraps inside optional chains.
    @Test func `Pausing and unpausing a scrolling label without a fade`() async throws {
        try #require(!UIAccessibility.isReduceMotionEnabled)
        // The label needs a rendered window to get a presentation layer, which is
        // what `awayFromHome` (and so `pauseLabel()`) reads.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        let label = makeLabel()
        label.animationDelay = 0
        label.speed = .rate(200)
        label.fadeLength = 0
        window.addSubview(label)
        window.isHidden = false
        defer { window.isHidden = true }
        label.layoutIfNeeded()
        CATransaction.flush()

        try await Task.sleep(for: .milliseconds(300))
        try #require(label.awayFromHome)

        label.pauseLabel()
        #expect(label.isPaused)
        label.unpauseLabel()
        #expect(!label.isPaused)
    }

    // MARK: - UILabel overrides

    /// Upstream handed super the old value (read back through the overridden
    /// getter) rather than the new one.
    @Test func `contentMode reaches the label itself`() {
        let label = makeLabel()
        label.contentMode = .center
        #expect(label.contentMode == .center)
        #expect(label.layer.contentsGravity == .center)
    }

    @Test func `Text properties are forwarded to the sublabel`() {
        let label = makeLabel(text: "Route 7")
        label.textColor = .red
        #expect(label.text == "Route 7")
        #expect(label.textColor == .red)
        #expect(label.numberOfLines == 1)
        label.numberOfLines = 3
        #expect(label.numberOfLines == 1)
    }
}
