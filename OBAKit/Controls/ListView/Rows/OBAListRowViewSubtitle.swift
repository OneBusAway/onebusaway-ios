//
//  OBAListRowViewSubtitle.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowViewSubtitle: OBAListRowView {
    static let ReuseIdentifier = "OBAListRowViewSubtitle_ReuseIdentifier"
    private var textStack: UIStackView!

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
    let subtitleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .footnote), textColor: ThemeColors.shared.secondaryLabel)

    override func makeUserView() -> UIView {
        self.textStack = UIStackView.stack(axis: .vertical, distribution: .equalSpacing, arrangedSubviews: [titleLabel, subtitleLabel])

        return self.textStack
    }

    override func configureView() {
        super.configureView()
        titleLabel.text = configuration.text
        titleLabel.configure(with: configuration.textConfig)

        subtitleLabel.text = configuration.secondaryText
        subtitleLabel.configure(with: configuration.secondaryTextConfig)

        isAccessibilityElement = true
        accessibilityLabel = configuration.text
        accessibilityValue = configuration.secondaryText
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
    }
}

// MARK: - Default ViewModel for convenience
extension OBAListRowView {
    /// For convenience, if you are tracking data separately from the view model or you are displaying UI with no data,
    /// you can use this view model to define a `subtitle` appearance list row.
    public struct SubtitleViewModel: OBAListViewItem {
        public let id: UUID = UUID()
        public var title: String
        public var subtitle: String?
        public var accessoryType: OBAListRowConfiguration.Accessory = .disclosureIndicator

        public var onSelectAction: OBAListViewAction<SubtitleViewModel>?

        public var contentConfiguration: OBAContentConfiguration {
            return OBAListRowConfiguration(text: title, secondaryText: subtitle, appearance: .subtitle, accessoryType: accessoryType)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        public static func == (lhs: SubtitleViewModel, rhs: SubtitleViewModel) -> Bool {
            return lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
                lhs.accessoryType == rhs.accessoryType
        }
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowViewSubtitle_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.fill"),
        text: "name",
        secondaryText: "address",
        appearance: .subtitle,
        accessoryType: .none)

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowViewSubtitle()
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))
        }
    }
}

#endif
