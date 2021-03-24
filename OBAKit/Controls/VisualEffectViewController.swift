//
//  VisualEffectViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// This view controller provides a built-in visual effect view in order to make it easier to
/// create view controllers with visual effect view backgrounds.
///
/// The visual effect view is created at object instantiation, and is pinned to the edges of
/// `view` in `viewDidLoad` with Auto Layout.
///
/// - Note: Subviews must be added to `visualEffectView.contentView`.
public class VisualEffectViewController: UIViewController {

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    /// Add subviews to this visual effect view.
    public let visualEffectView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.white.withAlphaComponent(0.50)

        return view
    }()

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(visualEffectView)
        visualEffectView.pinToSuperview(.edges)
    }

    var hasVisualEffectBackground: Bool { true }
}
