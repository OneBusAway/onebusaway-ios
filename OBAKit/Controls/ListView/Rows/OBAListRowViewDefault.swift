//
//  OBAListRowViewDefault.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowViewDefault: OBAListRowView {
    static let ReuseIdentifier = "OBAListRowViewDefault_ReuseIdentifier"

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))

    override func makeUserView() -> UIView {
        // wrap in stack view to fix layout spacing
        return UIStackView(arrangedSubviews: [titleLabel])
    }

    override func configureView() {
        super.configureView()
        titleLabel.setText(configuration.text)
        titleLabel.configure(with: configuration.textConfig)

        isAccessibilityElement = true
        if case let .string(string) = configuration.text {
            accessibilityLabel = string
        } else {
            accessibilityLabel = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
    }
}

// MARK: - Default ViewModel for convenience
extension OBAListRowView {
    /// For convenience, if you are tracking data separately from the view model or you are displaying UI with no data,
    /// you can use this view model to define a `default` appearance list row.
    public struct DefaultViewModel: OBAListViewItem {
        public let id: UUID = UUID()
        public var image: UIImage?
        public var title: OBAListRowConfiguration.LabelText
        public var accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator

        public var onSelectAction: OBAListViewAction<DefaultViewModel>?

        public var contentConfiguration: OBAContentConfiguration {
            return OBAListRowConfiguration(image: image, text: title, appearance: .default, accessoryType: accessoryType)
        }

        /// Convenience initializer for `DefaultViewModel` using `String` as text.
        public init(title: String, accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator, onSelectAction: OBAListViewAction<DefaultViewModel>? = nil) {
            self.title = .string(title)
            self.accessoryType = accessoryType
            self.onSelectAction = onSelectAction
        }

        /// Convenience initializer for `DefaultViewModel` using `NSAttributedString` as text.
        public init(title: NSAttributedString, accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator, onSelectAction: OBAListViewAction<DefaultViewModel>? = nil) {
            self.title = .attributed(title)
            self.accessoryType = accessoryType
            self.onSelectAction = onSelectAction
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(image)
            hasher.combine(title)
            hasher.combine(accessoryType)
        }

        public static func == (lhs: DefaultViewModel, rhs: DefaultViewModel) -> Bool {
            return
                lhs.id == rhs.id &&
                lhs.image == rhs.image &&
                lhs.title == rhs.title &&
                lhs.accessoryType == rhs.accessoryType
        }
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowViewDefault_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.fill"),
        text: .string("title text"),
        appearance: .default,
        accessoryType: .none)

    static let attributedConfiguration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.fill"),
        text: .attributed(attributedStringExample),
        appearance: .default,
        accessoryType: .none)

    static var attributedStringExample: NSAttributedString {
        let font = UIFont(name: "Zapfino", size: 32)!
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.red
        shadow.shadowBlurRadius = 5

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .shadow: shadow
        ]

        return NSAttributedString(string: "Zapfino", attributes: attributes)
    }

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowViewDefault(frame: .zero)
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowViewDefault(frame: .zero)
                view.configuration = attributedConfiguration
                return view
            }
            .previewLayout(.sizeThatFits)

            UIViewPreview {
                let view = OBAListRowViewDefault(frame: .zero)
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
