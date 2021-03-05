//
//  OBAListRowView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

// MARK: - Collection View Cell

/// A recreation of the default `UITableView` cells (or `UIListContentConfiguration`).
class OBAListRowCell<ListRowType: OBAListRowView>: OBAListViewCell {
    fileprivate let kUseDebugColors = false

    var listRowView: ListRowType! {
        didSet {
            if kUseDebugColors {
                listRowView.backgroundColor = .green
            }

            contentView.addSubview(listRowView)
            NSLayoutConstraint.activate([
                listRowView.leadingAnchor.constraint(equalTo: contentView.readableContentGuide.leadingAnchor),
                listRowView.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),
                listRowView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
                listRowView.bottomAnchor.constraint(greaterThanOrEqualTo: contentView.bottomAnchor)
            ])

            self.accessibilityElements = [listRowView!]
        }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.listRowView = ListRowType.autolayoutNew()
        contentView.addSubview(self.listRowView)
        self.listRowView.pinToSuperview(.edges)

        fixiOS13AutoLayoutBug()

        contentView.layer.addSublayer(separator)

        if kUseDebugColors {
            backgroundColor = .red
            contentView.backgroundColor = .magenta
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data
    override func apply(_ config: OBAContentConfiguration) {
        listRowView.apply(config)
    }

    // MARK: - Style

    public var style: CollectionController.TableCollectionStyle = .plain {
        didSet {
            contentView.backgroundColor = defaultBackgroundColor
        }
    }

    public var defaultBackgroundColor: UIColor? {
        if style == .plain {
            return nil
        }
        else {
            return ThemeColors.shared.groupedTableRowBackground
        }
    }

    // MARK: - UICollectionViewCell
    override func prepareForReuse() {
        super.prepareForReuse()
        listRowView.prepareForReuse()
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : defaultBackgroundColor
        }
    }
}

// MARK: - UIView

/// OBAListRowView provides the basics of a tableview-like cell. To
/// implement, subclass this. Make style-specific UIs by overriding
/// `makeUserView()`. For best results, make sure your
/// `userView` also adapts to content size changes.
///
/// # Layouts
/// ## Standard content size
/// ```
/// +--------UICollectionViewCell.contentView--------+
/// |+------------------outerStack------------------+|
/// ||+--------contentStack--------+                ||
/// |||imageView           userView|  accessoryView ||
/// ||+----------------------------+                ||
/// |+----------------------------------------------+|
/// +------------------------------------------------+
/// ```
/// ## Accessibility content size
/// ```
/// +--------UICollectionViewCell.contentView--------+
/// |+------------------outerStack------------------+|
/// ||+--------contentStack--------+                ||
/// |||imageView                   |                ||
/// |||                            |  accessoryView ||
/// |||userView                    |                ||
/// ||+----------------------------+                ||
/// |+----------------------------------------------+|
/// +------------------------------------------------+
/// ```
public class OBAListRowView: UIView, OBAContentView {
    var configuration: OBAListRowConfiguration = .init() {
        didSet {
            self.configureView()
        }
    }

    // MARK: - UI
    var contentStack: UIStackView!

    var userView: UIView!
    var imageView: UIImageView!
    private var accessoryView: UIImageView!

    lazy var rowHeightConstraint: NSLayoutConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minimumCellHeight)

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView = UIImageView.autolayoutNew()
        imageView.contentMode = .scaleAspectFit
        imageView.setCompressionResistance(horizontal: .required, vertical: .required)
        imageView.setHugging(horizontal: .required)
        imageView.tintColor = ThemeColors.shared.brand
        imageView.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .headline))

        accessoryView = UIImageView.autolayoutNew()
        accessoryView.setCompressionResistance(horizontal: .required, vertical: .required)
        accessoryView.setHugging(horizontal: .required)
        accessoryView.backgroundColor = .clear
        accessoryView.tintColor = ThemeColors.shared.brand
        accessoryView.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .body))

        userView = makeUserView()
        userView.setCompressionResistance(vertical: .defaultLow)

        contentStack = UIStackView.stack(
            axis: .horizontal,
            distribution: .fill,
            alignment: .center,
            arrangedSubviews: [imageView, userView])
        contentStack.spacing = ThemeMetrics.padding

        let outerStack = UIStackView.stack(axis: .horizontal, distribution: .fillProportionally, alignment: .center, arrangedSubviews: [contentStack, accessoryView])
        outerStack.spacing = ThemeMetrics.padding
        outerStack.backgroundColor = .clear

        addSubview(outerStack)

        outerStack.pinToSuperview(.readableContent) {
            $0.trailing.priority = .required - 1
        }

        configureView()

        NSLayoutConstraint.activate([rowHeightConstraint])
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureView()
    }

    public func apply(_ config: OBAContentConfiguration) {
        guard let listContentConfiguration = (config as? OBAListRowConfiguration) else { return }
        self.configuration = listContentConfiguration
    }

    func makeUserView() -> UIView {
        fatalError("makeUserView() not implemented.")
    }

    func configureView() {
        contentStack.axis = isAccessibility ? .vertical : .horizontal
        contentStack.alignment = isAccessibility ? .leading : .center

        let accessoryImage: UIImage?
        switch configuration.accessoryType {
        case .checkmark:
            accessoryImage = UIImage(systemName: "checkmark")
        case .detailButton:
            accessoryImage = UIImage(systemName: "info.circle")
        case .disclosureIndicator:
            accessoryImage = UIImage(systemName: "chevron.right")
        case .none:
            accessoryImage = nil
        }

        accessoryView.image = accessoryImage
        accessoryView.isHidden = accessoryView.image == nil

        imageView.image = configuration.image
        imageView.isHidden = imageView.image == nil

        rowHeightConstraint.constant = configuration.minimumCellHeight
    }

    func prepareForReuse() {
        self.imageView.image = nil
        self.accessoryView.image = nil
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowView_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.fill"),
        text: .string("name"),
        secondaryText: .string("address"),
        appearance: .subtitle,
        accessoryType: .disclosureIndicator)

    static var defaultRow: OBAListRowViewDefault {
        let row = OBAListRowViewDefault()
        row.apply(configuration)
        return row
    }

    static var subtitleRow: OBAListRowViewSubtitle {
        let row = OBAListRowViewSubtitle()
        row.apply(configuration)
        return row
    }

    static var valueRow: OBAListRowViewValue {
        let row = OBAListRowViewValue()
        row.apply(configuration)
        return row
    }

    static var previews: some View {
        Group {
            Group {
                UIViewPreview {
                    defaultRow
                }.previewDisplayName("Default")

                UIViewPreview {
                    subtitleRow
                }.previewDisplayName("Subtitle")

                UIViewPreview {
                    valueRow
                }.previewDisplayName("Value")
            }
            .previewLayout(.fixed(width: 384, height: 44))
            .previewDisplayName("Standard")

            Group {
                UIViewPreview {
                    defaultRow
                }.previewDisplayName("Default")

                UIViewPreview {
                    subtitleRow
                }.previewDisplayName("Subtitle")

                UIViewPreview {
                    valueRow
                }.previewDisplayName("Value")
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Acccessibility")
        }
    }
}

#endif
