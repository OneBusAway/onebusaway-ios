//
//  OBAListRowCellValue.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowCellValue: OBAListRowCell {
    static let ReuseIdentifier: String = "OBAListRowCellValue_ReuseIdentifier"

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
        subtitleLabel.text = configuration.secondaryText

        textStack.axis = isAccessibility ? .vertical : .horizontal
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellValue_Previews: PreviewProvider {
    static let configuration = OBAListContentConfiguration(image: UIImage(systemName: "person.fill"), text: "name", secondaryText: "address", appearance: .value, accessoryType: .none)
    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowCellValue()
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowCellValue()
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
