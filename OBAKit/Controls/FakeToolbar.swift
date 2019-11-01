//
//  FakeToolbar.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/1/19.
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
