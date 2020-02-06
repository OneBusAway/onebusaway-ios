//
//  TableRowView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/15/19.
//

import UIKit
import AloeStackView
import OBAKitCore

/// A view that approximates the appearance of a `UITableViewCell`. Meant to be used directly in an `AloeStackView`.
public class TableRowView: UIView, Highlightable {
    var kUseDebugColors = false

    /// The height constraint for this view.
    ///
    /// - Note: This is exposed primarily so that the constraint priority can be adjusted by `IGListKit` cells.
    var heightConstraint: NSLayoutConstraint!

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(contentStackWrapper)

        heightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        heightConstraint.priority = .required

        var constraints: [NSLayoutConstraint] = [
            heightConstraint,
            heightAnchor.constraint(greaterThanOrEqualTo: contentStack.heightAnchor),
            contentStackWrapper.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStackWrapper.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentStackWrapper.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStackWrapper.topAnchor.constraint(lessThanOrEqualTo: topAnchor, constant: ThemeMetrics.compactPadding),
            contentStackWrapper.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -ThemeMetrics.compactPadding)
        ]

        constraints.append(contentsOf: accessoryImageViewWrapper.vendedConstraints)
        constraints.append(contentsOf: imageWrapper.vendedConstraints)

        NSLayoutConstraint.activate(constraints)

        if kUseDebugColors {
            backgroundColor = .red
            imageWrapper.backgroundColor = .orange
            imageWrapper.imageView.backgroundColor = .magenta
            accessoryImageViewWrapper.imageView.backgroundColor = .purple
            accessoryImageViewWrapper.backgroundColor = .brown
            labelWrapper.backgroundColor = .yellow
            titleLabel.backgroundColor = .green
            subtitleLabel.backgroundColor = .blue
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data

    var data: TableRowData? {
        didSet {
            guard let data = data else { return }

            if let attributedTitle = data.attributedTitle {
                titleLabel.attributedText = attributedTitle
            }
            else {
                titleLabel.text = data.title
            }

            subtitleLabel.text = data.subtitle

            accessoryType = data.accessoryType

            imageWrapper.maxImageSize = data.imageSize ?? defaultImageWrapperSize

            if let image = data.image {
                imageWrapper.imageView.image = image

                if !contentStack.arrangedSubviews.contains(imageWrapper) {
                    contentStack.insertArrangedSubview(imageWrapper, at: 0)
                    contentStack.setCustomSpacing(ThemeMetrics.padding, after: imageWrapper)
                    imageWrapper.isHidden = false
                }
            }
            else {
                contentStack.removeArrangedSubview(imageWrapper)
                imageWrapper.isHidden = true
            }
        }
    }

    // MARK: - Image View

    private let defaultImageWrapperSize: CGFloat = 32.0

    private lazy var imageWrapper: ImageWrapper = {
        let wrapper = ImageWrapper(maxImageSize: defaultImageWrapperSize)
        return wrapper
    }()

    // MARK: - Accessory Types

    public var accessoryType: UITableViewCell.AccessoryType = .none {
        didSet {
            guard oldValue != accessoryType else { return }
            guard accessoryType != .none else {
                contentStack.removeArrangedSubview(accessoryImageViewWrapper)
                accessoryImageViewWrapper.isHidden = true
                return
            }

            if !contentStack.arrangedSubviews.contains(accessoryImageViewWrapper) {
                contentStack.addArrangedSubview(accessoryImageViewWrapper)
                accessoryImageViewWrapper.isHidden = false
            }

            accessoryImageViewWrapper.image = Icons.from(accessoryType: accessoryType)
        }
    }

    public var accessoryView: UIView? {
        didSet {
            if let oldValue = oldValue {
                contentStack.removeArrangedSubview(oldValue)
                oldValue.removeFromSuperview()
            }
            if let accessoryView = accessoryView {
                contentStack.insertArrangedSubview(accessoryView, at: 1)
            }
        }
    }

    private lazy var accessoryImageViewWrapper = ImageWrapper(maxImageSize: 20.0)

    // MARK: - UIAppearance Selectors

    @objc dynamic var titleFont: UIFont {
        get { return titleLabel.font }
        set { titleLabel.font = newValue }
    }

    @objc dynamic var subtitleFont: UIFont {
        get { return subtitleLabel.font }
        set { subtitleLabel.font = newValue }
    }

    // MARK: - UI Configuration

    lazy var contentStackWrapper = contentStack.embedInWrapperView()

    /// This is the outermost stack view embedded within this cell. Accessory views should be added to this view.
    lazy var contentStack: UIStackView = {
        let stack = UIStackView.horizontalStack(arrangedSubviews: [imageWrapper, labelWrapper, accessoryImageViewWrapper])
        stack.setCustomSpacing(ThemeMetrics.padding, after: imageWrapper)
        return stack
    }()

    private lazy var labelWrapper = labelStack.embedInWrapperView()
    lazy var labelStack = UIStackView.verticalStack(arangedSubviews: [titleLabel, subtitleLabel])

    let titleLabel = TableRowView.buildLabel()
    let subtitleLabel: UILabel = {
        let label = TableRowView.buildLabel()
        label.textColor = ThemeColors.shared.secondaryLabel

        return label
    }()

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        return label
    }

    // MARK: - UICollectionViewCell-alikes

    public func prepareForReuse() {
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    // MARK: - Highlightable

    public func setIsHighlighted(_ isHighlighted: Bool) {
      guard let cell = superview as? StackViewCell else { return }
        cell.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : cell.rowBackgroundColor
    }
}

// MARK: - Default Cell

class DefaultTableRowView: TableRowView {

    public convenience init(title: String, accessoryType: UITableViewCell.AccessoryType) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        data = TableRowData(title: title, attributedTitle: nil, subtitle: nil, style: .default, accessoryType: accessoryType, tapped: nil)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        labelStack.removeArrangedSubview(subtitleLabel)
        subtitleLabel.removeFromSuperview()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Value Cell

class ValueTableRowView: TableRowView {
    public convenience init(title: String, subtitle: String, accessoryType: UITableViewCell.AccessoryType) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        data = TableRowData(title: title, attributedTitle: nil, subtitle: subtitle, style: .value1, accessoryType: accessoryType, tapped: nil)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        labelStack.axis = .horizontal
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

        subtitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        subtitleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Subtitle Cell

class SubtitleTableRowView: TableRowView {
    public convenience init(title: String, subtitle: String, accessoryType: UITableViewCell.AccessoryType) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        data = TableRowData(title: title, attributedTitle: nil, subtitle: subtitle, style: .subtitle, accessoryType: accessoryType, tapped: nil)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        labelStack.axis = .vertical
        labelStack.alignment = .fill

        let spacer = UIView.autolayoutNew()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        if kUseDebugColors {
            spacer.backgroundColor = .purple
        }

        labelStack.insertArrangedSubview(spacer, at: 2)

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - ImageWrapper

fileprivate class ImageWrapper: UIView {
    var maxImageSize: CGFloat {
        didSet {
            updateConstraintConstants()
        }
    }

    private func updateConstraintConstants() {
        imageViewHeight.constant = min(maxImageSize, image?.size.height ?? CGFloat.greatestFiniteMagnitude)
        imageViewWidth.constant = min(maxImageSize, image?.size.width ?? CGFloat.greatestFiniteMagnitude)
        wrapperHeight.constant = maxImageSize
    }

    lazy var imageViewHeight = imageView.heightAnchor.constraint(equalToConstant: maxImageSize)
    lazy var imageViewWidth = imageView.widthAnchor.constraint(equalToConstant: maxImageSize)
    lazy var wrapperHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: maxImageSize)
    lazy var wrapperWidth = widthAnchor.constraint(equalTo: imageView.widthAnchor)

    var vendedConstraints: [NSLayoutConstraint] {
        [imageViewHeight, imageViewWidth, wrapperHeight, wrapperWidth]
    }

    let imageView: UIImageView = {
        let imageView = UIImageView.autolayoutNew()
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return imageView
    }()

    init(maxImageSize: CGFloat) {
        self.maxImageSize = maxImageSize

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        setContentHuggingPriority(.required, for: .horizontal)

        wrapperWidth.priority = .required

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            if newValue != nil {
                updateConstraintConstants()
            }
        }
    }
}
