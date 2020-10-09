//
//  OBAListRowView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import SwipeCellKit
import OBAKitCore

// MARK: - Collection View Cell

class OBAListViewCell<ListRowType: OBAListRowView>: SwipeCollectionViewCell, OBAContentView, ReuseIdentifierProviding, Separated {
    fileprivate let kUseDebugColors = false

    fileprivate var tableRowView: ListRowType! {
        didSet {
            if kUseDebugColors {
                tableRowView.backgroundColor = .green
            }

            contentView.addSubview(tableRowView)
            NSLayoutConstraint.activate([
                tableRowView.leadingAnchor.constraint(equalTo: contentView.readableContentGuide.leadingAnchor),
                tableRowView.trailingAnchor.constraint(equalTo: contentView.readableContentGuide.trailingAnchor),
                tableRowView.topAnchor.constraint(equalTo: contentView.topAnchor),
                tableRowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                tableRowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0)
            ])

            self.accessibilityElements = [tableRowView!]
        }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.tableRowView = ListRowType.autolayoutNew()
        contentView.addSubview(self.tableRowView)
        self.tableRowView.pinToSuperview(.edges)

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
    func apply(_ config: OBAContentConfiguration) {
        tableRowView.apply(config)
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
//        tableRowView.prepareForReuse()
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.backgroundColor = isHighlighted ? ThemeColors.shared.highlightedBackgroundColor : defaultBackgroundColor
        }
    }

    // MARK: - Separator

    /// When true, the cell will extend the separator all the way to its leading edge.
    public var collapseLeftInset: Bool = false

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset: CGFloat? = collapseLeftInset ? 0 : nil
        layoutSeparator(leftSeparatorInset: inset)
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
    var configuration: OBAListContentConfiguration = .init() {
        didSet {
            self.configureView()
        }
    }

    // MARK: - UI
    var contentStack: UIStackView!
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setCompressionResistance(vertical: .required)
        view.setHugging(horizontal: .defaultHigh)
        view.tintColor = ThemeColors.shared.brand
        view.preferredSymbolConfiguration = .init(font: .preferredFont(forTextStyle: .headline))

        return view
    }()

    var userView: UIView!
    private var accessoryView: UIImageView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.userView = makeUserView()
        self.contentStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .leading, arrangedSubviews: [imageView, userView])
        contentStack.spacing = ThemeMetrics.padding

        accessoryView = UIImageView.autolayoutNew()
        accessoryView.setCompressionResistance(vertical: .required)
        accessoryView.setHugging(horizontal: .defaultHigh)
        accessoryView.backgroundColor = .clear

        let outerStack = UIStackView.stack(axis: .horizontal, distribution: .fill, alignment: .center, arrangedSubviews: [contentStack, accessoryView])
        outerStack.spacing = ThemeMetrics.padding
        outerStack.backgroundColor = .clear

        addSubview(outerStack)

        outerStack.pinToSuperview(.readableContent) {
            $0.trailing.priority = .required - 1
        }

        configureView()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        configureView()
    }

    public func apply(_ config: OBAContentConfiguration) {
        guard let listContentConfiguration = (config as? OBAListContentConfiguration) else { return }
        self.configuration = listContentConfiguration
    }

    func makeUserView() -> UIView {
        fatalError("makeUserView() not implemented.")
    }
    
    func configureView() {
        imageView.image = configuration.image

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
        self.accessoryView.image = accessoryImage
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
    static let configuration = OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: "name", secondaryText: "address", appearance: .subtitle, accessoryType: .disclosureIndicator)

    static var defaultRow: OBAListRowCellDefault {
        let row = OBAListRowCellDefault()
        row.apply(configuration)
        return row
    }

    static var subtitleRow: OBAListRowCellSubtitle {
        let row = OBAListRowCellSubtitle()
        row.apply(configuration)
        return row
    }

    static var valueRow: OBAListRowCellValue {
        let row = OBAListRowCellValue()
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
