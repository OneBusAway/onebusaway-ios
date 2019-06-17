//
//  TableRowView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/15/19.
//

import UIKit

/// A view that approximates the appearance of a `UITableViewCell`.
///
/// - Note: Nominally, this is meant to be used in an `AloeStackView` or with `IGListKit`.

public class TableRowView: UIView {

    var useDebugColors = false

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(contentStack)
        contentStack.pinToSuperview(.edges)

        let heightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            heightConstraint, imageViewHeight, imageViewWidth, imageViewWrapperHeight, imageViewWrapperWidth
        ])

        if useDebugColors {
            backgroundColor = .red
            accessoryImageView.backgroundColor = .red
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

            configureAccessoryType(with: data.accessoryType, oldValue: oldValue?.accessoryType)
        }
    }

    // MARK: - Accessory Types

    private func configureAccessoryType(
        with accessoryType: UITableViewCell.AccessoryType,
        oldValue: UITableViewCell.AccessoryType?
    ) {
        guard oldValue != accessoryType else { return }

        guard accessoryType != .none else {
            accessoryImageViewWrapper.removeFromSuperview()
            return
        }

        if accessoryImageViewWrapper.superview == nil {
            contentStack.insertSubview(accessoryImageViewWrapper, belowSubview: labelWrapper)
        }

        accessoryImageView.image = Icons.from(accessoryType: accessoryType)

        if let image = accessoryImageView.image {
            imageViewHeight.constant = min(maxImageSize, image.size.height)
            imageViewWidth.constant = min(maxImageSize, image.size.width)
        }
    }

    // MARK: - UIAppearance Selectors

    @objc dynamic var titleFont: UIFont {
        get { return titleLabel.font }
        set { titleLabel.font = newValue }
    }

    @objc dynamic var subtitleFont: UIFont {
        get { return subtitleLabel.font }
        set { subtitleLabel.font = newValue }
    }

    @objc dynamic var subtitleTextColor: UIColor {
        get { return subtitleLabel.textColor }
        set { subtitleLabel.textColor = newValue }
    }

    // MARK: - UI Configuration

    /// This is the outermost stack view embedded within this cell. Accessory views should be added to this view.
    lazy var contentStack = UIStackView.horizontalStack(arrangedSubviews: [labelWrapper, accessoryImageViewWrapper])

    private lazy var labelWrapper = labelStack.embedInWrapperView()
    lazy var labelStack = UIStackView.verticalStack(arangedSubviews: [titleLabel, subtitleLabel])

    let titleLabel = TableRowView.buildLabel()
    let subtitleLabel = TableRowView.buildLabel()

    private class func buildLabel() -> UILabel {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.backgroundColor = .clear
        return label
    }

    // MARK: - Accessory Image View

    private let maxImageSize: CGFloat = 20.0
    private lazy var imageViewHeight: NSLayoutConstraint = accessoryImageView.heightAnchor.constraint(equalToConstant: maxImageSize)
    private lazy var imageViewWidth: NSLayoutConstraint = accessoryImageView.widthAnchor.constraint(equalToConstant: maxImageSize)
    private lazy var imageViewWrapperHeight: NSLayoutConstraint = accessoryImageViewWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: maxImageSize)
    private lazy var imageViewWrapperWidth: NSLayoutConstraint = accessoryImageViewWrapper.widthAnchor.constraint(equalToConstant: maxImageSize)

    private let accessoryImageView = UIImageView.autolayoutNew()

    private lazy var accessoryImageViewWrapper: UIView = {
        let view = accessoryImageView.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            accessoryImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            accessoryImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }()

    // MARK: - UICollectionViewCell-alikes

    public func prepareForReuse() {
        titleLabel.text = nil
        subtitleLabel.text = nil
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

        if useDebugColors {
            spacer.backgroundColor = .purple
        }

        labelStack.insertArrangedSubview(spacer, at: 2)

        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
