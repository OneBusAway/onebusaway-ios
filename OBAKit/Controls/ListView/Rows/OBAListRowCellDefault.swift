//
//  OBAListRowCellDefault.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

public class OBAListRowCellDefault: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowCellDefault_ReuseIdentifier"

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))

    override func makeUserView() -> UIView {
        // wrap in stack view to fix layout spacing
        return UIStackView(arrangedSubviews: [titleLabel])
    }

    override func configureView() {
        super.configureView()
        titleLabel.text = configuration.text
        titleLabel.configure(with: configuration.textConfig)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellDefault_Previews: PreviewProvider {
    static let configuration = OBAListRowConfiguration(image: UIImage(systemName: "person.fill"), text: "title text", appearance: .default, accessoryType: .none)

    static var previews: some View {
        Group {
            UIViewPreview {
                let view = OBAListRowCellDefault(frame: .zero)
                view.configuration = configuration
                return view
            }
            .previewLayout(.fixed(width: 384, height: 44))

            UIViewPreview {
                let view = OBAListRowCellDefault(frame: .zero)
                view.configuration = configuration
                return view
            }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewLayout(.sizeThatFits)
        }
    }
}

#endif
