//
//  OBAListRowCellHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

public class OBAListRowCellHeader: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowCellDefault_ReuseIdentifier"

    public var section: OBAListViewSection? {
        didSet {
            guard let section = section else { return }

            if let collapseState = section.collapseState {
                let image: UIImage

                switch collapseState {
                case .collapsed:    image = UIImage(systemName: "chevron.right.circle.fill")!
                case .expanded:     image = UIImage(systemName: "chevron.down.circle.fill")!
                }

                self.configuration = OBAListRowConfiguration(image: image, text: section.title, appearance: .header)
            } else {
                self.configuration = OBAListRowConfiguration(text: section.title, appearance: .header)
            }
        }
    }

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .headline))

    override func makeUserView() -> UIView {
        // wrap in stack view to fix layout spacing
        return UIStackView.stack(distribution: .equalSpacing, arrangedSubviews: [titleLabel])
    }

    override func configureView() {
        super.configureView()
        self.backgroundColor = UIColor.secondarySystemBackground

        titleLabel.text = configuration.text

        isAccessibilityElement = true
        accessibilityLabel = configuration.text
        accessibilityTraits = .header
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellHeader_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(
        image: UIImage(systemName: "person.circle.fill"),
        text: "Privacy Settings",
        appearance: .header,
        accessoryType: .none)

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowCellHeader(frame: .zero)
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowCellHeader(frame: .zero)
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
