//
//  OnDemandPickerViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// Classic-shell host for the overlap picker: a navigation controller so a
/// row tap pushes the service page inside the same sheet.
final class OnDemandPickerViewController: UINavigationController {

    private let makeDetail: (OnDemandServiceMatch, OnDemandLocationCheck) -> OnDemandServiceViewController?
    private let onHighlight: (String?) -> Void

    /// - Parameter makeDetail: builds a row's service page, with the probe's
    ///   geometry for its thumbnail.
    init(
        model: OnDemandPickerModel,
        makeDetail: @escaping (OnDemandServiceMatch, OnDemandLocationCheck) -> OnDemandServiceViewController?,
        onHighlight: @escaping (String?) -> Void
    ) {
        self.makeDetail = makeDetail
        self.onHighlight = onHighlight
        super.init(nibName: nil, bundle: nil)
        setNavigationBarHidden(true, animated: false)

        let picker = OnDemandPickerView(
            model: model,
            onHighlight: onHighlight,
            onSelect: { [weak self] match, check in self?.select(match, check: check) },
            onClose: { [weak self] in self?.dismiss(animated: true) }
        )
        viewControllers = [UIHostingController(rootView: picker)]
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Pushes the service page for a picked row.
    func select(_ match: OnDemandServiceMatch, check: OnDemandLocationCheck) {
        guard let detail = makeDetail(match, check) else { return }
        setNavigationBarHidden(false, animated: true)
        pushViewController(detail, animated: true)
    }

    override func popViewController(animated: Bool) -> UIViewController? {
        let popped = super.popViewController(animated: animated)
        if viewControllers.count == 1 {
            setNavigationBarHidden(true, animated: animated)
        }
        return popped
    }

    /// Fires when the whole sheet is dismissed (close button or swipe), not
    /// when a row pushes the detail inside it, so the highlight survives the
    /// push (spec 3.5).
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onHighlight(nil)
    }
}
