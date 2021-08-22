//
//  Created by Brian M Coyner on 4/18/17.
//  Copyright © 2017 Brian Coyner. All rights reserved.
//

import Foundation
import UIKit

class HoverBar: HoverBarPassThroughView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    let stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 2
        stack.axis = .vertical
        stack.distribution = .fill
        stack.alignment = .fill
        return stack
    }()
}

/// The view has the following features:
/// - drop shadow provided by a dynamically generated 9-part image.
/// - rounded corners
/// - live blur effect
/// - automatically adjusts for changes to the `UIUserInterfaceStyle` (i.e. light/dark)
///   - if `.light`, then a drop shadow displays; blur effect is "light material"
///   - if `.dark`, then the drop shadow is hidden; blur effect is "dark material"
///
/// Developers add subviews to the `contentView` property.
/// Developers should not add subviews directly to this view.
///
class HoverBarPassThroughView: UIView {

    // Developers add subviews to the `contentView`.
    var contentView: UIView {
        return visualEffectView.contentView
    }

    // Debug option for drawing the shadow image cap insets.
    var showCapInsetLines: Bool = false {
        didSet {
            shadowView.image = resizeableShadowImage(
                withCornerRadius: Properties.cornerRadius,
                shadow: Properties.shadow,
                shouldDrawCapInsets: showCapInsetLines
            )
        }
    }

    var showShadow: Bool = true {
        didSet {
            shadowView.isHidden = !showShadow
        }
    }

    fileprivate lazy var shadowView = self.lazyShadowView()
    fileprivate lazy var visualEffectView = self.lazyVisualEffectView()

    convenience init() {
        self.init(frame: CGRect())
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.selfInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.selfInit()
    }

    private func selfInit() {
        backgroundColor = .clear

        // Putting the shadow view under the visual effect view helps
        // reduce any strange image view artifacts that may appear.

        addSubview(shadowView)
        addSubview(visualEffectView)

        let blurRadius = Properties.shadow.blur
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),

            shadowView.topAnchor.constraint(equalTo: topAnchor, constant: -blurRadius),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: blurRadius),
            shadowView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: blurRadius),
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -blurRadius)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            transition(to: traitCollection.userInterfaceStyle)
        }
    }

    private func transition(to style: UIUserInterfaceStyle) {
        switch style {
        case .light, .unspecified:
            showShadow = true
        case .dark:
            showShadow = false
        @unknown default:
            fatalError()
        }
    }

    fileprivate func lazyVisualEffectView() -> UIVisualEffectView {
        // The "system thin" material automatically adapts to changes to the `UIUserInterfaceStyle`.
        // The only we need to do here is show/ hide the shadow.
        let blurEffect = UIBlurEffect(style: .systemThickMaterial)

        let view = UIVisualEffectView(effect: blurEffect)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Properties.cornerRadius
        view.layer.masksToBounds = true

        return view
    }

    fileprivate func lazyShadowView() -> UIImageView {
        let image = resizeableShadowImage(
            withCornerRadius: Properties.cornerRadius,
            shadow: Properties.shadow,
            shouldDrawCapInsets: showCapInsetLines
        )

        let view = UIImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }

    fileprivate func resizeableShadowImage(
        withCornerRadius cornerRadius: CGFloat,
        shadow: Shadow,
        shouldDrawCapInsets: Bool
    ) -> UIImage {

        // Trial and error: a multiple of 5 seems to create a decent shadow image for our purposes.
        // It's not a perfect fit with the visual effect view's corner. However, putting the image
        // view under the visual effect view should mask any issues. 
        let sideLength: CGFloat = cornerRadius * 5
        return UIImage.resizableShadowImage(
            withSideLength: sideLength,
            cornerRadius: cornerRadius,
            shadow: shadow,
            shouldDrawCapInsets: showCapInsetLines
        )
    }

    private enum Properties {
        static let cornerRadius: CGFloat = 8.0
        static let shadow: Shadow = Shadow(offset: CGSize(), blur: 6.0, color: .systemGray)
    }
}
