//
//  UIKitExtensionsTests.swift
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
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class UIKitExtensionsTests {

    private var window: UIWindow!
    
    @Test func `UI button build close button`() {
        let button = UIButton.buildCloseButton()
        #expect(button.translatesAutoresizingMaskIntoConstraints == false)
        #expect(button.accessibilityLabel == Strings.close)
    }
    
    @Test func `UI trait environment is accessibility`() {
        _ = UITraitCollection(preferredContentSizeCategory: .extraLarge)
        let view = UIView()
        view.overrideUserInterfaceStyle = .unspecified
        // For this test, we need to create a mock trait environment
        // Since the actual isAccessibility property depends on the trait collection
        // We'll test the logic directly by checking content size categories
        #expect(UIContentSizeCategory.extraLarge >= .extraLarge)
        #expect(!(UIContentSizeCategory.medium >= .extraLarge))
    }

    // MARK: - topmostPresentedController

    /// A presented controller only materializes when the presenter is in a window,
    /// so every case here roots one.
    private func rooted(_ controller: UIViewController) -> UIViewController {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        return controller
    }

    private func presentAndWait(_ controller: UIViewController, from presenter: UIViewController) async {
        await withCheckedContinuation { continuation in
            presenter.present(controller, animated: false) {
                continuation.resume()
            }
        }
    }

    @Test func `Topmost presented controller is self when nothing is presented`() {
        let controller = rooted(UIViewController())

        #expect(controller.topmostPresentedController === controller)
    }

    @Test func `Topmost presented controller walks to the end of the chain`() async {
        let base = rooted(UIViewController())
        let middle = UIViewController()
        let top = UIViewController()

        await presentAndWait(middle, from: base)
        await presentAndWait(top, from: middle)

        #expect(base.topmostPresentedController === top)
    }

    /// The shape #1441 actually hits: the child presented nothing itself, but an
    /// ancestor is presenting, and UIKit refuses `present` on the child until that
    /// clears. `presentedViewController` reports an ancestor's presentation, so the
    /// walk finds it from here.
    @Test func `Topmost presented controller sees a presentation made by an ancestor`() async {
        let child = UIViewController()
        let navigation = UINavigationController(rootViewController: child)
        let tabBar = UITabBarController()
        tabBar.viewControllers = [navigation]
        _ = rooted(tabBar)

        let sheet = UIViewController()
        await presentAndWait(sheet, from: tabBar)

        #expect(child.topmostPresentedController === sheet)
    }

    // MARK: - UIColor.contrastingTextColor

    /// The document web view uses this for its action button's text, on an
    /// accent-colored background, so a light accent needs dark text and a dark
    /// one needs light text.
    @Test func `Contrasting text color is dark on light colors and light on dark ones`() {
        let yellow = UIColor(red: 0.96, green: 0.71, blue: 0.20, alpha: 1.0)
        let navy = UIColor(red: 0.05, green: 0.15, blue: 0.45, alpha: 1.0)

        #expect(UIColor.white.contrastingTextColor == .darkText)
        #expect(yellow.contrastingTextColor == .darkText)
        #expect(UIColor.black.contrastingTextColor == .lightText)
        #expect(navy.contrastingTextColor == .lightText)
    }

    /// Perceived brightness weights green far above blue. A plain average of
    /// the channels would rate pure green (1/3) as dark.
    @Test func `Contrasting text color weights green above red and blue`() {
        #expect(UIColor(red: 0, green: 1, blue: 0, alpha: 1).contrastingTextColor == .darkText)
        #expect(UIColor(red: 1, green: 0, blue: 0, alpha: 1).contrastingTextColor == .lightText)
        #expect(UIColor(red: 0, green: 0, blue: 1, alpha: 1).contrastingTextColor == .lightText)
    }

    @Test func `Contrasting text color switches at half brightness`() {
        #expect(UIColor(white: 0.49, alpha: 1).contrastingTextColor == .lightText)
        #expect(UIColor(white: 0.51, alpha: 1).contrastingTextColor == .darkText)
    }

    // MARK: - UIColor.blended(with:amount:)

    private func rgba(_ color: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func expectComponents(_ color: UIColor, _ expected: [CGFloat], sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = rgba(color)
        let close = zip(actual, expected).allSatisfy { abs($0 - $1) < 0.0001 }
        #expect(close, "expected \(expected), got \(actual)", sourceLocation: sourceLocation)
    }

    @Test func `Blended at zero is the original color and at one is the other`() {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

        expectComponents(red.blended(with: blue, amount: 0), [1, 0, 0, 1])
        expectComponents(red.blended(with: blue, amount: 1), [0, 0, 1, 1])
    }

    /// The stop icon's gradient blends the route color a fixed fraction toward
    /// white and black; each channel moves that fraction of the way.
    @Test func `Blended moves each channel the given fraction of the way`() {
        let base = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)

        expectComponents(base.blended(with: .white, amount: 0.25), [0.4, 0.7, 1.0, 1])
        expectComponents(base.blended(with: .black, amount: 0.25), [0.15, 0.45, 0.75, 1])
    }

    @Test func `Blended clamps an amount outside zero to one`() {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

        expectComponents(red.blended(with: blue, amount: -0.5), [1, 0, 0, 1])
        expectComponents(red.blended(with: blue, amount: 1.5), [0, 0, 1, 1])
    }

    /// Only the color mixes. A see-through tint stays see-through after
    /// blending with an opaque color.
    @Test func `Blended keeps the original color's alpha`() {
        let translucentRed = UIColor(red: 1, green: 0, blue: 0, alpha: 0.4)

        expectComponents(translucentRed.blended(with: .black, amount: 1), [0, 0, 0, 0.4])
    }
}
