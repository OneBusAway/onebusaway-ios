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
// - Embedded in a FloatingPanel (the stop sheet): every navigation controller under the
//   vertical tab bar insets its pages by the column's width, without checking whether it
//   reaches the column. `preferredVerticalBarBehavior` isn't consulted below the window's root
//   there, so `SheetNavigationController` takes the excess back out of its pages' safe area.
//
// Sheets with bar items of their own (Schedules, the map settings sheet) are left alone: their
// glyph buttons are what fills the column.

extension UIViewController {
    /// `.disabled` while this controller is part of a presented sheet. A controller pushed onto
    /// the window's own navigation stack stays `.automatic`, because its preference reaches the
    /// window and would lay the tab bar out horizontally.
    @available(iOS 27.1, *)
    var sheetVerticalBarBehavior: UIVerticalBarBehavior {
        presentingViewController == nil ? .automatic : .disabled
    }
}

/// A hosting controller for a sheet with no bar items, which keeps its bars horizontal.
class SheetHostingController<Content: View>: UIHostingController<Content> {
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        sheetVerticalBarBehavior
    }
}

/// A navigation controller for a sheet, which keeps its bars horizontal whether it is
/// presented or embedded in a FloatingPanel.
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
        viewController.view.layoutIfNeeded()
        matchHorizontalSafeArea(of: viewController)
    }

    /// Caps a page's leading and trailing safe area at this controller's own. A page that
    /// overlaps the bar column for real keeps the inset, because this view carries it too.
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
