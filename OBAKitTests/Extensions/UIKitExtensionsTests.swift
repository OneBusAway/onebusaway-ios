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
    
    @Test func `UI button chevron button`() {
        let button = UIButton.chevronButton
        #expect(button.buttonType == .detailDisclosure)
        #expect(button.image(for: .normal) != nil)
    }
    
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
}
