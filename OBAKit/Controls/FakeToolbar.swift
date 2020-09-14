//
//  FakeToolbar.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// A container control that sort of looks like a UIToolbar, but offers more customization options and fewer issues.
class FakeToolbar: UIView {

    /// The host for all of the controls in this toolbar. Add and remove `arrangedSubviews` here.
    let stackView: UIStackView

    /// The wrapper view for the `stackView` is exposed to allow you to customize the safe area
    /// insets of the toolbar when using this view on an iPhone X-class device.
    lazy var stackWrapper = stackView.embedInWrapperView()

    /// Initializes the `FakeToolbar`, giving you an opportunity to populate the toolbar.
    /// - Parameter toolbarItems: The views that will populate the toolbar.
    init(toolbarItems: [UIView]) {
        stackView = UIStackView.horizontalStack(arrangedSubviews: toolbarItems)
        stackView.spacing = ThemeMetrics.padding
        stackView.alignment = .center
        stackView.distribution = .fillEqually

        super.init(frame: .zero)

        addSubview(hairline)

        let blurContainerView = VisualEffectContainerView(blurEffect: UIBlurEffect(style: .light))
        blurContainerView.translatesAutoresizingMaskIntoConstraints = false
        blurContainerView.contentView.addSubview(stackWrapper)

        addSubview(blurContainerView)

        blurContainerView.pinToSuperview(.edges)

        NSLayoutConstraint.activate([
            stackWrapper.leadingAnchor.constraint(equalTo: blurContainerView.contentView.leadingAnchor),
            stackWrapper.trailingAnchor.constraint(equalTo: blurContainerView.contentView.trailingAnchor),
            stackWrapper.topAnchor.constraint(equalTo: blurContainerView.contentView.topAnchor)
        ])

        addInteraction(UILargeContentViewerInteraction())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let hairline: UIView = {
        let view = UIView()
        view.backgroundColor = ThemeColors.shared.separator
        return view
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        bringSubviewToFront(hairline)

        hairline.frame = CGRect(x: 0, y: 0, width: frame.width, height: 1.0 / UIScreen.main.scale)
    }

    // MARK: - Class Methods

    class func buildToolbarButton(title: String, image: UIImage, target: Any, action: Selector) -> UIButton {
        let button = ProminentButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        button.addTarget(target, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)])
        button.showsLargeContentViewer = true
        button.scalesLargeContentImage = true
        return button
    }
}
