//
//  SheetControllers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit

// MARK: - Sheets keep their bars horizontal

// Where the system presents bars vertically (iPhone Duo), a sheet reserves the bar column down
// its trailing edge — ~84pt that stays empty unless the sheet has bar items to put there. The
// sheets below have none, so they keep their bars across the top, as they do on other iPhones.
//
// How the column gets in differs with how the sheet is shown, so the fix does too:
//
// - Presented (`present(_:animated:)`): the sheet is a presentation of its own, and opts out
//   with `preferredVerticalBarBehavior`, which UIKit reads from the root of each presentation.
//   A SwiftUI `.sheet` does the same with `sheetKeepsBarsHorizontal()`.
// - Embedded in a FloatingPanel (the stop sheet): every navigation controller under the
//   vertical tab bar insets its pages by the column's width, without checking whether it
//   reaches the column. `preferredVerticalBarBehavior` isn't consulted below the window's root
//   there, so `SheetNavigationController` takes the excess back out of its pages' safe area.
//
// Sheets with glyph bar items of their own (Schedules, the map settings sheet) are left alone:
// those buttons are what fills the column.

fileprivate extension UIViewController {
    /// `.disabled` while presented. A controller pushed onto the window's own navigation stack
    /// stays `.automatic`, because its preference reaches the window and would lay the tab bar
    /// out horizontally.
    @available(iOS 27.1, *)
    var sheetVerticalBarBehavior: UIVerticalBarBehavior {
        presentingViewController == nil ? .automatic : .disabled
    }
}

extension View {
    /// The content of a SwiftUI `.sheet` with no bar items, which keeps its bars horizontal.
    @ViewBuilder
    func sheetKeepsBarsHorizontal() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}

/// A hosting controller for a sheet with no bar items, which keeps its bars horizontal.
class SheetHostingController<Content: View>: UIHostingController<Content> {
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        sheetVerticalBarBehavior
    }
}

/// A navigation controller for a sheet, presented or embedded, which keeps its bars horizontal.
class SheetNavigationController: UINavigationController {
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        sheetVerticalBarBehavior
    }

    /// The sheet decides for all of its pages, so one that would choose differently can't
    /// put the column back as it is pushed.
    @available(iOS 27.1, *)
    override var childForPreferredVerticalBarBehavior: UIViewController? {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForVerticalBarChanges { [weak self] in self?.resetHorizontalSafeAreaCorrections() }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        resetHorizontalSafeAreaCorrections()
    }

    /// UIKit clamps a safe area inset at zero, so once a correction has brought a page's inset
    /// to zero, the page no longer shows how much of it is still needed. The column only comes
    /// and goes with the window's size or the vertical bar traits, so at those moments the
    /// corrections are dropped and the next layout pass measures afresh.
    private func resetHorizontalSafeAreaCorrections() {
        for viewController in viewControllers {
            var additional = viewController.additionalSafeAreaInsets
            additional.left = 0
            additional.right = 0
            if additional != viewController.additionalSafeAreaInsets {
                viewController.additionalSafeAreaInsets = additional
            }
        }
        viewIfLoaded?.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for viewController in viewControllers where viewController.isViewLoaded {
            matchHorizontalSafeArea(of: viewController)
        }
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        // The pushed page joins the hierarchy here, before the next layout pass of this
        // controller's own view; correcting it now keeps the gap from showing mid-transition.
        guard viewController.viewIfLoaded?.window != nil else { return }
        viewController.view.layoutIfNeeded()
        matchHorizontalSafeArea(of: viewController)
    }

    /// Caps a page's leading and trailing safe area at this controller's own. It owns the
    /// pages' left and right `additionalSafeAreaInsets`; a page can't set its own.
    private func matchHorizontalSafeArea(of viewController: UIViewController) {
        guard viewController.view.window != nil else { return }
        let additional = Self.correctedAdditionalSafeArea(
            page: viewController.view.safeAreaInsets,
            additional: viewController.additionalSafeAreaInsets,
            container: view.safeAreaInsets
        )
        if additional != viewController.additionalSafeAreaInsets {
            viewController.additionalSafeAreaInsets = additional
        }
    }

    /// `additional` with its left and right set to take back whatever a page's inset on that
    /// side exceeds `container`'s. Top and bottom pass through: the navigation bar legitimately
    /// adds to the top.
    nonisolated static func correctedAdditionalSafeArea(
        page: UIEdgeInsets,
        additional: UIEdgeInsets,
        container: UIEdgeInsets
    ) -> UIEdgeInsets {
        var corrected = additional
        // What UIKit gives the page before this correction.
        let left = page.left - additional.left
        let right = page.right - additional.right
        corrected.left = -max(0, left - container.left)
        corrected.right = -max(0, right - container.right)
        return corrected
    }
}
