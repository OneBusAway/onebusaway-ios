//
//  EmptyDataSetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// Provides a implementation of the 'empty data set' UI pattern.
/// To add a button, set `button.config`. See `ActivityIndicatedButton.Configuration` for more details.
public class EmptyDataSetView: UIView {
    public enum EmptyDataSetAlignment {
        case top, center
    }

    // MARK: - Constants
    fileprivate static let DefaultColor = ThemeColors.shared.secondaryLabel

    // MARK: - Properties
    /// The font used on the title label.
    @objc public dynamic var titleLabelFont: UIFont {
        set { titleLabel.font = newValue }
        get { titleLabel.font }
    }

    /// The font used on the body label.
    @objc public dynamic var bodyLabelFont: UIFont {
        set { bodyLabel.font = newValue }
        get { bodyLabel.font }
    }

    /// The tint color used on the image view. If this is nil, it will default to using `textColor`.
    @objc public dynamic var imageTintColor: UIColor? {
        didSet {
            imageView.tintColor = imageTintColor ?? textColor
        }
    }

    /// The text color used for the title and body labels. Also used by `imageView` if `imageTintColor` is `nil`.
    @objc public dynamic var textColor: UIColor {
        set {
            titleLabel.textColor = newValue
            bodyLabel.textColor = newValue
            imageView.tintColor = imageTintColor ?? textColor
        }
        get { return titleLabel.textColor }
    }

    /// Configuration for the button. Set to `nil` to hide the button. See `ButtonConfig.init` for additional details.
    // MARK: - UI
    fileprivate let alignment: EmptyDataSetAlignment

    fileprivate lazy var imageViewHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 64)
    public let imageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.tintColor = EmptyDataSetView.DefaultColor
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)

        return imageView
    }()

    /// The title label. This property is exposed primarily to let you set the `text` property.
    public let titleLabel: UILabel = {
        let label = UILabel.obaLabel(font: UIFont.preferredFont(forTextStyle: .title1).bold,
                                     textColor: EmptyDataSetView.DefaultColor)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    /// The body label. This property is exposed primarily to let you set the `text` property.
    public let bodyLabel: UILabel = {
        let label = UILabel.obaLabel(textColor: EmptyDataSetView.DefaultColor)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.textAlignment = .center
        label.backgroundColor = .clear
        return label
    }()

    public let button = ActivityIndicatedButton(config: nil)

    fileprivate lazy var stackView: UIStackView = {
        let stack = UIStackView.stack(axis: .vertical,
                                      distribution: .fill,
                                      alignment: .center,
                                      arrangedSubviews: [imageView, titleLabel, bodyLabel, button])
        stack.setCustomSpacing(ThemeMetrics.padding, after: imageView)
        stack.setCustomSpacing(ThemeMetrics.compactPadding, after: titleLabel)
        stack.setCustomSpacing(ThemeMetrics.padding, after: bodyLabel)

        return stack
    }()

    // MARK: - Initializers

    public init(alignment: EmptyDataSetAlignment = .center) {
        self.alignment = alignment
        super.init(frame: .zero)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            imageViewHeightConstraint,
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor)
        ])

        // TOOD: Use readableContentGuides instead of layoutMarginsGuide.
        // The same issue as #263 exists here too.

        // Bottom constraint to ensure content doesn't continue flowing past the bottom
        // because it might not be a scroll view.
        let top = stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor)
        let leading = stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)
        let trailing = stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        let bottom = stackView.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor)
        let centerY = stackView.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor)

        let isCentered = alignment == .center
        top.priority        = isCentered ? .defaultLow : .required
        centerY.priority    = isCentered ? .required : .defaultLow
        bottom.priority     = isCentered ? .defaultLow : .required

        // Priorities necessary here when width==0 in the very beginning.
        leading.priority    = .defaultHigh
        trailing.priority   = .defaultHigh

        NSLayoutConstraint.activate([top, leading, trailing, bottom, centerY])

        layoutView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func layoutView() {
        let isAccessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        imageViewHeightConstraint.constant = isAccessibility ? 96 : 64
        layoutIfNeeded()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        self.layoutView()
    }

    // MARK: - Configure with error
    public func configure(with error: Error, icon: UIImage? = nil, buttonConfig: ActivityIndicatedButton.Configuration? = nil) {
        self.bodyLabel.text = error.localizedDescription
        self.button.config = buttonConfig
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
struct EmptyDataSetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Group {
                centerAlignment
                    .previewDisplayName("Light mode")

                centerAlignment
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Dark mode")
            }.previewDisplayName("Color scheme")

            centerAlignment
                .environment(\.sizeCategory, .accessibilityLarge)
                .previewDisplayName("Accessibility Large")

            topAlignment
                .previewDisplayName("Top alignment")
        }
        .previewLayout(.sizeThatFits)
    }

    static var centerAlignment: some View {
        UIViewPreview {
            let view = EmptyDataSetView(alignment: .center)
            view.imageView.image = UIImage(systemName: "flame.fill")
            view.titleLabel.text = "Get rid of tab bar"
            view.bodyLabel.text = "In my quest for the very best accessibility, one change I made is defaulting the map drawer to be full screen when the user is in voiceover. The map is difficult (in my experience) to navigate in voiceover and it is more helpful to provide a list of data instead of the map."
            return view
        }
    }

    static var topAlignment: some View {
        UIViewPreview {
            let view = EmptyDataSetView(alignment: .top)
            view.imageView.image = UIImage(systemName: "flame.fill")
            view.titleLabel.text = "Get rid of tab bar"
            view.bodyLabel.text = "In my quest for the very best accessibility, one change I made is defaulting the map drawer to be full screen when the user is in voiceover. The map is difficult (in my experience) to navigate in voiceover and it is more helpful to provide a list of data instead of the map."
            return view
        }
    }
}
#endif
