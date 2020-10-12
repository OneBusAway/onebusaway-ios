//
//  OBAListRowViewValue.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowViewValue: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowViewValue_ReuseIdentifier"

    private var textStack: UIStackView!

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))
    let subtitleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body), textColor: ThemeColors.shared.secondaryLabel)

    override func makeUserView() -> UIView {
        titleLabel.textAlignment = .left
        subtitleLabel.textAlignment = .right

        self.textStack = UIStackView.stack(axis: .horizontal, distribution: .fill, arrangedSubviews: [titleLabel, subtitleLabel])

        return self.textStack
    }

    override func configureView() {
        super.configureView()
        titleLabel.text = configuration.text
        titleLabel.configure(with: configuration.textConfig)

        subtitleLabel.text = configuration.secondaryText
        subtitleLabel.configure(with: configuration.secondaryTextConfig)

        textStack.axis = isAccessibility ? .vertical : .horizontal

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

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowViewValue_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.fill"),
        text: "name",
        secondaryText: "address",
        appearance: .value,
        accessoryType: .none)

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowViewValue()
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowViewValue()
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
