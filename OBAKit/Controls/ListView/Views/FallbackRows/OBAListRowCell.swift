//
//  OBAListRowCell.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

/// OBAListRowCell provides the basics of a tableview-like cell. To
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
public class OBAListRowCell: UICollectionViewCell, OBAListContentConfigurable {
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

    public func configure(with config: OBAListContentConfiguration) {
        self.configuration = config
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
        case .detailDisclosureButton:
            accessoryImage = UIImage(systemName: "info.circle")
        case .disclosureIndicator:
            accessoryImage = UIImage(systemName: "chevron.right")
        case .none:
            accessoryImage = nil
        @unknown default:
            accessoryImage = nil
        }
        self.accessoryView.image = accessoryImage

//        isAccessibilityElement = true
//        accessibilityTraits = [.button, .staticText]
//        accessibilityLabel = configuration.text
//        accessibilityLabel = Strings.serviceAlert
//        accessibilityValue = configuration.secondaryText
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension OBAListRowCell {
    static var allRows: [OBAListRowCell.Type] {
        return [
            OBAListRowCellDefault.self,
            OBAListRowCellSubtitle.self,
            OBAListRowCellValue.self,
            OBAListRowCellHeader.self
        ]
    }

    static func row(for config: OBAListContentConfiguration) -> OBAListRowCell.Type {
        switch config.appearance {
        case .default:  return OBAListRowCellDefault.self
        case .subtitle: return OBAListRowCellSubtitle.self
        case .value:    return OBAListRowCellValue.self
        case .header:   return OBAListRowCellHeader.self
        }
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
        row.configure(with: configuration)
        return row
    }

    static var subtitleRow: OBAListRowCellSubtitle {
        let row = OBAListRowCellSubtitle()
        row.configure(with: configuration)
        return row
    }

    static var valueRow: OBAListRowCellValue {
        let row = OBAListRowCellValue()
        row.configure(with: configuration)
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
