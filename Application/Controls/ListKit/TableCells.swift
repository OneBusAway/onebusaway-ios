//
//  TableCells.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/15/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit

class TableRowCell: SelfSizingCollectionCell {

    fileprivate let kUseDebugColors = false

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.addSublayer(separator)

        contentView.addSubview(contentStack)
        contentStack.pinToSuperview(.layoutMargins)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0),
            imageViewHeight, imageViewWidth, imageViewWrapperHeight, imageViewWrapperWidth
        ])

        if (kUseDebugColors) {
            backgroundColor = .red
            accessoryImageView.backgroundColor = .red
            accessoryImageViewWrapper.backgroundColor = .brown
            labelWrapper.backgroundColor = .yellow
            contentView.backgroundColor = .magenta
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
            guard let data = data else {
                return
            }

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

    private func configureAccessoryType(with accessoryType: UITableViewCell.AccessoryType, oldValue: UITableViewCell.AccessoryType?) {
        guard oldValue != accessoryType else {
            return
        }

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

    private var _highlightedBackgroundColor = UIColor(white: 0.9, alpha: 1.0)
    @objc dynamic var highlightedBackgroundColor: UIColor {
        get { return _highlightedBackgroundColor }
        set { _highlightedBackgroundColor = newValue }
    }

    private var _leftSeparatorInset: CGFloat = 20.0
    @objc dynamic var leftSeparatorInset: CGFloat {
        get { return _leftSeparatorInset }
        set { _leftSeparatorInset = newValue }
    }

    @objc dynamic var separatorColor: UIColor {
        get { return UIColor(cgColor: separator.backgroundColor!) }
        set { separator.backgroundColor = newValue.cgColor }
    }

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

    let titleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.backgroundColor = .clear

        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.numberOfLines = 0
        label.backgroundColor = .clear

        return label
    }()

    // MARK: - Accessory Image View

    let maxImageSize: CGFloat = 20.0
    lazy var imageViewHeight: NSLayoutConstraint = accessoryImageView.heightAnchor.constraint(equalToConstant: maxImageSize)
    lazy var imageViewWidth: NSLayoutConstraint = accessoryImageView.widthAnchor.constraint(equalToConstant: maxImageSize)
    lazy var imageViewWrapperHeight: NSLayoutConstraint = accessoryImageViewWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: maxImageSize)
    lazy var imageViewWrapperWidth: NSLayoutConstraint = accessoryImageViewWrapper.widthAnchor.constraint(equalToConstant: maxImageSize)

    private let accessoryImageView = UIImageView.autolayoutNew()

    private lazy var accessoryImageViewWrapper: UIView = {
        let view = accessoryImageView.embedInWrapperView(setConstraints: false)
        NSLayoutConstraint.activate([
            accessoryImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            accessoryImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }()

    // MARK: - UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? highlightedBackgroundColor : .clear
        }
    }

    let separator: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor(red: 200 / 255.0, green: 199 / 255.0, blue: 204 / 255.0, alpha: 1).cgColor
        return layer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let height: CGFloat = 0.5
        separator.frame = CGRect(x: leftSeparatorInset, y: bounds.height - height, width: bounds.width - leftSeparatorInset, height: height)
    }
}

// MARK: - Default Cell

class DefaultTableCell: TableRowCell {
    override init(frame: CGRect) {
        super.init(frame: frame)

        labelStack.removeArrangedSubview(subtitleLabel)
        subtitleLabel.removeFromSuperview()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Value Cell

class ValueTableCell: TableRowCell {
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

class SubtitleTableCell: TableRowCell {
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

        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        subtitleLabel.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class TableSectionHeaderView: UICollectionReusableView {

    let textLabel: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
        return label
    }()

    @objc dynamic var font: UIFont {
        get { return textLabel.font }
        set { textLabel.font = newValue }
    }

    override var backgroundColor: UIColor? {
        didSet {
            textLabel.backgroundColor = backgroundColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textLabel)
        backgroundColor = UIColor(white: 0.95, alpha: 0.95)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: self.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textLabel.text = nil
    }
}
