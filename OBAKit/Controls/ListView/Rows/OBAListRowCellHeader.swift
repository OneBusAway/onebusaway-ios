//
//  OBAListRowCellHeader.swift
//  OBAKit
//
//  Created by Alan Chu on 10/4/20.
//

import OBAKitCore

public class OBAListRowCellHeader: OBAListRowView {
    static let ReuseIdentifier: String = "OBAListRowCellDefault_ReuseIdentifier"

    let titleLabel: UILabel = .obaLabel(font: .preferredFont(forTextStyle: .body))

    override func makeUserView() -> UIView {
        // wrap in stack view to fix layout spacing
        return UIStackView(arrangedSubviews: [titleLabel])
    }

    override func configureView() {
        super.configureView()
        self.backgroundColor = UIColor.secondarySystemBackground

        titleLabel.text = configuration.text
    }
}

// MARK: - Preview
#if DEBUG
import SwiftUI
import OBAKitCore

struct OBAListRowCellHeader_Previews: PreviewProvider {
    static let configuration = OBAListContentConfiguration(image: UIImage(systemName: "person.circle.fill"), text: "Privacy Settings", appearance: .header, accessoryType: .none)

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
