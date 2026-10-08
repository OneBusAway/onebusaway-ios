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

/// Skips a test that needs the label to scroll, which it won't with Reduce Motion on.
private extension Trait where Self == ConditionTrait {
    static var reduceMotionOff: Self {
        .enabled("Reduce Motion stops MarqueeLabel scrolling") {
            await MainActor.run { !UIAccessibility.isReduceMotionEnabled }
        }
    }
}

/// Covers the vendored MarqueeLabel in `OBAKit/ThirdParty/MarqueeLabel`,
/// including regressions for the `OBA:` fixes made there.
@MainActor
@Suite(.serialized)
struct MarqueeLabelTests {

    private static let longText = String(repeating: "Downtown Seattle via Rainier Ave S ", count: 4)
    private static let font = UIFont.preferredFont(forTextStyle: .footnote)

    private func makeLabel(text: String = longText, width: CGFloat = 100) -> MarqueeLabel {
        let label = MarqueeLabel(frame: CGRect(x: 0, y: 0, width: width, height: 20))
        label.font = Self.font
        label.text = text
        return label
    }

    /// Shows `label` in a window. The label needs a rendered window to get a
    /// presentation layer, which `awayFromHome` and `animationPosition` read.
    private func show(_ label: MarqueeLabel) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        window.addSubview(label)
        window.isHidden = false
        label.layoutIfNeeded()
        CATransaction.flush()
        return window
    }

    /// Shows a long label that starts scrolling as soon as it's on screen.
    private func showScrollingLabel(configure: (MarqueeLabel) -> Void = { _ in }) throws -> (MarqueeLabel, UIWindow) {
        let label = makeLabel()
        label.animationDelay = 0
        label.speed = .rate(200)
        configure(label)
        return (label, try show(label))
    }

    // MARK: - labelShouldScroll

    @Test(.reduceMotionOff) func `Text wider than the label scrolls`() {
        #expect(makeLabel().labelShouldScroll())
    }

    @Test func `Text that fits does not scroll`() {
        #expect(!makeLabel(text: "1").labelShouldScroll())
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
    @Test(.reduceMotionOff) func `Auto-shrinking label with a zero scale factor scrolls`() {
        let label = makeLabel()
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0
        #expect(label.labelShouldScroll())
    }

    @Test func `Auto-shrinking label that fits once shrunk does not scroll`() {
        let text = "Rainier Ave S"
        let fullWidth = (text as NSString).size(withAttributes: [.font: Self.font]).width
        let label = makeLabel(text: text, width: ceil(fullWidth * 0.75))
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        #expect(!label.labelShouldScroll())
    }

    @Test(.reduceMotionOff) func `Auto-shrinking label that is too wide even when shrunk scrolls`() {
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

    // MARK: - On screen

    /// Upstream compared the layer's center with the home frame's origin, so a
    /// label at rest read as away from home.
    @Test func `A label at rest is at home`() async throws {
        let label = makeLabel(text: "1")
        let window = try show(label)
        defer { window.isHidden = true }
        await spin(0.1)

        #expect(!label.awayFromHome)
        #expect(label.animationPosition == 0)
    }

    @Test(.reduceMotionOff) func `A scrolling label leaves home`() async throws {
        let (label, window) = try showScrollingLabel()
        defer { window.isHidden = true }

        await poll(until: { label.awayFromHome })
        #expect((label.animationPosition ?? 0) > 0)
    }

    /// `labelWasTapped` and `triggerScrollStart()` only start a scroll from home,
    /// which upstream's `awayFromHome` never reported.
    @Test(.reduceMotionOff) func `triggerScrollStart starts a held label`() async throws {
        let (label, window) = try showScrollingLabel { $0.holdScrolling = true }
        defer { window.isHidden = true }
        await spin(0.1)
        try #require(!label.awayFromHome)

        label.triggerScrollStart()
        CATransaction.flush()
        await poll(until: { label.awayFromHome })
    }

    // MARK: - Pausing

    /// The fade mask is absent when `fadeLength` is 0, and pausing reaches it
    /// through force unwraps inside optional chains.
    @Test(.reduceMotionOff) func `Pausing and unpausing a scrolling label without a fade`() async throws {
        let (label, window) = try showScrollingLabel { $0.fadeLength = 0 }
        defer { window.isHidden = true }
        await poll(until: { label.awayFromHome })

        label.pauseLabel()
        #expect(label.isPaused)
        label.unpauseLabel()
        #expect(!label.isPaused)
    }

    /// A scroll sits at home during its delay; pausing then still has to work.
    @Test(.reduceMotionOff) func `Pausing a scrolling label during its delay at home`() async throws {
        let (label, window) = try showScrollingLabel { $0.animationDelay = 10 }
        defer { window.isHidden = true }
        await spin(0.1)
        try #require(!label.awayFromHome)

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
